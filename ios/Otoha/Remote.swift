import Combine
import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

struct InfraredStatus {
  let receiverId, phase: String
  var label: String?
  var message: String?
  var devices: [LocalBlaster]?
}

struct Receiver {
  let device: HKDevice
  let sources: [ReceiverInput]
  let actions: [String]
  var online = false
  var infrared: InfraredStatus?
  var trackedMode: String?
  var lastSource: String?
  var model: String { device.model }
  var speaker: Bool { device.profile == "mm" }
  var irWake: Bool { infrared?.phase == "linked" }
  var emitterLabel: String? { irWake ? infrared?.label : nil }
}

@MainActor final class Remote: ObservableObject {
  @Published private(set) var receiver: Receiver?
  @Published private(set) var busy = false
  @Published private(set) var feedback: String?
  @Published private(set) var pulse = 0
  var activity: String { receiver.map { $0.online ? "Connected" : "Stereo offline" } ?? "Choose your stereo" }
  var canWake: Bool { receiver?.online == true || receiver?.irWake == true }

  private let discover: () async throws -> [HKDevice]
  private let defaults: UserDefaults
  private let monitor = NWPathMonitor()
  private var lastPath: NWPath?
  private var epoch = 0
  private var refreshing = false
  private var verified = false
  private var lastSearch = Date.distantPast
  private var found: [HKDevice] = []
  private var foundAt = Date.distantPast
  private var volumeStep: Task<Bool, Never>?
  private var feedbackTask: Task<Void, Never>?
  private static let modes = ["High", "Low", "Off"]
  private static let selectionKey = "directReceiver.v1"

  init(defaults: UserDefaults = .standard, discover: @escaping () async throws -> [HKDevice] = HarmanNetwork.discover) {
    self.discover = discover
    self.defaults = defaults
    struct OldEquipment: Decodable { let device: HKDevice? }
    let saved = defaults.data(forKey: Self.selectionKey).flatMap { try? JSONDecoder().decode(HKDevice.self, from: $0) }
    let previous = defaults.data(forKey: "lastRemoteEquipment.v1").flatMap { try? JSONDecoder().decode(OldEquipment.self, from: $0) }
    if let device = saved ?? previous?.device { receiver = snapshot(device) }
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        if let lastPath = self.lastPath, lastPath != path { self.disconnected() }
        self.lastPath = path
      }
    }
    monitor.start(queue: DispatchQueue(label: "otoha.wifi"))
  }
  deinit { monitor.cancel() }

  private func blaster(for device: HKDevice) -> LocalBlaster? {
    defaults.data(forKey: "directIR." + device.id).flatMap { try? JSONDecoder().decode(LocalBlaster.self, from: $0) }
  }

  private func snapshot(_ device: HKDevice) -> Receiver? {
    guard let profile = HarmanCatalog.shared.profiles[device.profile] else { return nil }
    var result = Receiver(device: device, sources: profile.sources.filter { device.model != "HK 3700" || $0.id != "bluetooth" },
                          actions: profile.keys.keys.filter { device.model == "HK 3770" || $0 != "harman" })
    if device.model == "HK 3770" {
      let ir = blaster(for: device)
      let label = ir?.label
      result.infrared = InfraredStatus(receiverId: device.id, phase: label == nil ? "idle" : "linked", label: label)
    }
    return result
  }

  func disconnected() {
    epoch += 1
    verified = false
    lastSearch = .distantPast
    found = []
    receiver?.online = false
    receiver?.trackedMode = nil
    receiver?.lastSource = nil
    if let device = receiver?.device { receiver?.infrared = snapshot(device)?.infrared }
  }

  private func accept(_ device: HKDevice) throws {
    guard var state = snapshot(device) else { throw RemoteError("This model isn’t supported.") }
    let bytes = try JSONEncoder().encode(device)
    if defaults.data(forKey: Self.selectionKey) != bytes { defaults.set(bytes, forKey: Self.selectionKey) }
    state.online = true
    receiver = state
    verified = true
  }

  func locateDevices() async throws -> [HKDevice] {
    guard !busy, volumeStep == nil else { throw RemoteError("Finish the current action and search again.") }
    busy = true
    epoch += 1
    let version = epoch
    defer { busy = false }
    found = []
    let devices = try await discover()
    try check(version)
    found = devices
    foundAt = Date()
    return devices
  }

  private func check(_ version: Int) throws {
    try Task.checkCancellation()
    guard epoch == version else { throw RemoteError("The connection changed. Try again.") }
  }

  func linkDevice(_ id: String) async throws {
    guard !busy, volumeStep == nil, Date().timeIntervalSince(foundAt) < 120, let candidate = found.first(where: { $0.id == id }) else {
      throw RemoteError("Search again and choose your stereo.")
    }
    busy = true
    epoch += 1
    let version = epoch
    defer { busy = false }
    let device: HKDevice?
    if let url = candidate.descriptionURL {
      device = try? await HarmanNetwork.describe(url)
    } else {
      device = try await discover().first { $0.id == id }
    }
    guard let device, device.id == id, device.model == candidate.model, await HarmanNetwork.online(device) else {
      throw RemoteError("Your stereo didn’t answer. Turn it on and search again.")
    }
    try check(version)
    try accept(device)
  }

  func refresh() async {
    guard !busy, volumeStep == nil, !refreshing, let saved = receiver?.device else { return }
    refreshing = true
    defer { refreshing = false }
    let version = epoch
    if verified {
      let online = await HarmanNetwork.online(saved)
      guard version == epoch, !Task.isCancelled else { return }
      if !online { disconnected() }
      return
    }
    // A sleeping receiver can be offline for hours. Keep its remote and IR wake available.
    guard Date().timeIntervalSince(lastSearch) >= 90 else { return }
    lastSearch = Date()
    var match: HKDevice?
    if let url = saved.descriptionURL, let device = try? await HarmanNetwork.describe(url),
       device.id == saved.id, device.model == saved.model { match = device }
    if match == nil {
      match = try? await discover().first { $0.id == saved.id && $0.model == saved.model }
    }
    guard let match, version == epoch, !Task.isCancelled, await HarmanNetwork.online(match),
          version == epoch, !Task.isCancelled else { return }
    try? accept(match)
  }

  @discardableResult func send(_ action: String, _ value: String? = nil) async -> Bool {
    guard !busy, let state = receiver, state.online || (action == "wake" && state.irWake) else { return false }
    if action == "louder" || action == "quieter" {
      guard volumeStep == nil else { return false }
      let step = Task { await perform(action, value, state: state) }
      volumeStep = step
      defer { volumeStep = nil }
      return await step.value
    }
    busy = true
    defer { busy = false }
    if let step = volumeStep {
      guard await step.value, !Task.isCancelled, receiver?.device.id == state.device.id, receiver?.online == true else { return false }
    }
    return await perform(action, value, state: state)
  }

  private func perform(_ action: String, _ value: String?, state: Receiver) async -> Bool {
    let device = state.device
    guard let profile = HarmanCatalog.shared.profiles[device.profile] else { return false }
    epoch += 1
    let version = epoch
    var message = "Command sent."
    do {
      if action == "wake", let ir = blaster(for: device) {
        if ir.kind == .itach { notify("Looking for your iTach. This can take a minute.") }
        let current = try await DirectInfrared.resolve(ir)
        try check(version)
        try await DirectInfrared.operate(current, send: true)
        message = "Infrared On signal sent."
      } else if action == "sync-mode" || action == "set-mode" {
        guard device.model == "HK 3770", let value, let target = Self.modes.firstIndex(of: value) else { return false }
        if action == "set-mode" {
          guard let mode = receiver?.trackedMode, let from = Self.modes.firstIndex(of: mode), let key = profile.keys["harman"] else {
            throw RemoteError("Sync the mode with the receiver display first.")
          }
          for step in 0..<((target - from + 3) % 3) {
            if step > 0 { try await Task.sleep(for: .milliseconds(340)) }
            try check(version)
            _ = try await HarmanNetwork.transmit(device, packets: [profile.packet(key)])
          }
        }
        try check(version)
        receiver?.trackedMode = value
        message = "Tracking " + value + "."
      } else {
        var packets: [Data]
        if action == "source", let source = state.sources.first(where: { $0.id == value }), let wire = source.wire {
          packets = [profile.packet("source-selection", value: wire, zone: source.zone ?? "Main Zone")]
          if device.profile == "stereo" && source.id == "usb" { packets.append(profile.packet("source-selection", value: "iPod")) }
          message = source.name + " requested."
        } else if action == "speaker-volume", state.speaker, let level = value.flatMap(Int.init), (0...100).contains(level) {
          packets = [profile.packet("set_system_volume", value: String(level))]
        } else if state.actions.contains(action), let key = profile.keys[action] {
          packets = [profile.packet(key)]
        } else { return false }
        _ = try await HarmanNetwork.transmit(device, packets: packets)
        try check(version)
        if action == "source" { receiver?.lastSource = value }
        if action == "harman", let mode = receiver?.trackedMode, let from = Self.modes.firstIndex(of: mode) {
          receiver?.trackedMode = Self.modes[(from + 1) % 3]
        }
      }
      try check(version)
      if action == "standby" || action == "wake" { receiver?.trackedMode = nil; receiver?.lastSource = nil; lastSearch = .distantPast }
      if action != "louder" && action != "quieter" { pulse += 1; notify(message) }
      return true
    } catch {
      if ["harman","set-mode"].contains(action) { receiver?.trackedMode = nil }
      notify(error.localizedDescription)
      return false
    }
  }

  func configureInfrared(_ action: String, receiverId: String, id: String? = nil) async throws {
    guard !busy, volumeStep == nil, let device = receiver?.device, device.id == receiverId, device.model == "HK 3770" else {
      throw RemoteError("Open infrared setup for your HK 3770 again.")
    }
    busy = true
    defer { busy = false }
    epoch += 1
    let version = epoch
    let key = "directIR." + device.id
    if action == "forget" {
      defaults.removeObject(forKey: key)
      receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "idle")
      return
    }
    guard blaster(for: device) == nil else { throw RemoteError("Forget the linked blaster before adding another one.") }
    do {
      let choice: LocalBlaster
      if action == "search" || action == "itach" {
        receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "searching")
        let devices = try await DirectInfrared.discover(itach: action == "itach")
        try check(version)
        guard let first = devices.first else { throw RemoteError("No blasters found. Check the blaster’s power and Wi-Fi, then search again.") }
        if devices.count > 1 {
          receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "choose", devices: devices)
          return
        }
        choice = first
      } else if action == "select", let candidate = receiver?.infrared?.devices?.first(where: { $0.id == id }) {
        choice = candidate
      } else { throw RemoteError("Find your blaster again.") }
      receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "linking")
      try await DirectInfrared.operate(choice, send: false)
      try check(version)
      defaults.set(try JSONEncoder().encode(choice), forKey: key)
      receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "linked", label: choice.label)
    } catch {
      if version == epoch { receiver?.infrared = snapshot(device)?.infrared }
      throw error
    }
  }

  func notify(_ text: String) {
    feedbackTask?.cancel()
    feedback = text
    #if canImport(UIKit)
    UIAccessibility.post(notification: .announcement, argument: text)
    #endif
    feedbackTask = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { feedback = nil }
    }
  }
}
