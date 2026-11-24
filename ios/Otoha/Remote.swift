import Combine
import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

struct InfraredStatus {
  let receiverId, phase: String
  var label: String?
  var devices: [LocalBlaster]?
}

struct Receiver {
  enum Connection: String {
    case connecting = "Connecting…"
    case connected = "Connected"
    case offline = "Stereo offline"
  }

  let device: HKDevice
  let sources: [ReceiverInput]
  let actions: [String]
  var connection: Connection = .connecting
  var online: Bool { connection == .connected }
  var infrared: InfraredStatus?
  var harmanVolume = HarmanVolume()
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
  var canWake: Bool { receiver?.actions.contains("wake") == true || receiver?.irWake == true }

  private let discover: () async throws -> [HKDevice]
  private let discoverBlasters: (Bool, Bool) async throws -> [LocalBlaster]
  private let defaults: UserDefaults
  private let monitor = NWPathMonitor()
  private var lastPath: NWPath?
  private struct ConnectionEpoch: Equatable {
    var operation = 0
    var path = 0
  }
  private var epoch = ConnectionEpoch()
  private var refreshingEpoch: ConnectionEpoch?
  private var nextRediscovery = ContinuousClock.Instant.now
  private var found: [HKDevice] = []
  private var foundAt = Date.distantPast
  private var volumeStep: Task<Bool, Never>?
  private var feedbackTask: Task<Void, Never>?
  private static let harmanPressInterval = Duration.milliseconds(600)
  private var nextHarmanPress = ContinuousClock.Instant.now.advanced(by: Remote.harmanPressInterval)
  private static let selectionKey = "directReceiver.v1"
  private static let pendingOfferKey = "pendingInfraredOffer.v1"

  var hasPendingInfraredOffer: Bool {
    guard let state = receiver, state.infrared != nil, !state.irWake else { return false }
    return defaults.string(forKey: Self.pendingOfferKey) == state.device.id
  }

  func finishInfraredOffer(for id: String) {
    guard receiver?.device.id == id else { return }
    defaults.set(true, forKey: "infraredOfferSeen." + id)
    defaults.removeObject(forKey: Self.pendingOfferKey)
  }

  init(defaults: UserDefaults = .standard, discover: @escaping () async throws -> [HKDevice] = HarmanNetwork.discover,
       discoverBlasters: @escaping (Bool, Bool) async throws -> [LocalBlaster] = DirectInfrared.discover) {
    self.discover = discover
    self.discoverBlasters = discoverBlasters
    self.defaults = defaults
    struct OldEquipment: Decodable { let device: HKDevice? }
    let saved = defaults.data(forKey: Self.selectionKey).flatMap { try? JSONDecoder().decode(HKDevice.self, from: $0) }
    let previous = defaults.data(forKey: "lastRemoteEquipment.v1").flatMap { try? JSONDecoder().decode(OldEquipment.self, from: $0) }
    if let device = saved ?? previous?.device { receiver = snapshot(device) }
    monitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        if let lastPath = self.lastPath, lastPath != path { self.networkPathChanged() }
        self.lastPath = path
      }
    }
    monitor.start(queue: DispatchQueue(label: "otoha.wifi"))
  }
  deinit { monitor.cancel() }

  private func blaster(for device: HKDevice) -> LocalBlaster? {
    guard let method = device.infraredWake, let bytes = defaults.data(forKey: "directIR." + device.id),
          let saved = try? JSONDecoder().decode(LocalBlaster.self, from: bytes) else { return nil }
    switch method {
    case .hk37xx:
      guard saved.learnedOn == nil, saved.learnedForModel == nil else { return nil }
    case .learnOn:
      guard saved.kind == .broadlink, saved.learnedForModel == device.model,
            let signal = saved.learnedOn, BroadLink.validLearnedSignal(signal) else { return nil }
    }
    return saved
  }

  private func snapshot(_ device: HKDevice) -> Receiver? {
    guard let profile = HarmanCatalog.shared.profiles[device.profile] else { return nil }
    var result = Receiver(device: device, sources: profile.sources.filter { device.model != "HK 3700" || $0.id != "bluetooth" },
                          actions: profile.keys.keys.filter { device.model == "HK 3770" || $0 != "harman" })
    if result.actions.contains("harman") { result.harmanVolume = .saved(for: device.id, in: defaults) }
    if device.infraredWake != nil {
      let ir = blaster(for: device)
      let label = ir?.label
      result.infrared = InfraredStatus(receiverId: device.id, phase: label == nil ? "idle" : "linked", label: label)
    }
    return result
  }

  func networkPathChanged() {
    epoch.path += 1
    resetConnection()
  }

  func disconnected() {
    epoch.operation += 1
    resetConnection()
  }

  func becameActive() {
    guard receiver?.online == false else { return }
    receiver?.connection = .connecting
    nextRediscovery = .now
  }

  private func resetConnection() {
    nextRediscovery = .now
    found = []
    if receiver?.online == true { receiver?.connection = .offline }
    receiver?.lastSource = nil
    if let device = receiver?.device { receiver?.infrared = snapshot(device)?.infrared }
  }

  private func accept(_ device: HKDevice) throws {
    guard var state = snapshot(device) else { throw RemoteError("This model isn’t supported.") }
    let bytes = try JSONEncoder().encode(device)
    if defaults.data(forKey: Self.selectionKey) != bytes { defaults.set(bytes, forKey: Self.selectionKey) }
    state.connection = .connected
    receiver = state
  }

  func locateDevices() async throws -> [HKDevice] {
    guard !busy, volumeStep == nil else { throw RemoteError("Finish the current action and search again.") }
    busy = true
    epoch.operation += 1
    let version = epoch
    defer { busy = false }
    found = []
    do {
      return try await scanDevices(on: version)
    } catch {
      try Task.checkCancellation()
      // A search can start over on a new path while the same operation is active.
      guard epoch.operation == version.operation, epoch.path != version.path else { throw error }
      return try await scanDevices(on: epoch)
    }
  }

  private func scanDevices(on version: ConnectionEpoch) async throws -> [HKDevice] {
    try check(version)
    let devices = try await discover()
    try check(version)
    found = devices
    foundAt = Date()
    return devices
  }

  private func check(_ version: ConnectionEpoch) throws {
    try Task.checkCancellation()
    guard epoch == version else { throw RemoteError("The connection changed. Try again.") }
  }

  func linkDevice(_ id: String) async throws {
    guard !busy, volumeStep == nil, Date().timeIntervalSince(foundAt) < 120, let candidate = found.first(where: { $0.id == id }) else {
      throw RemoteError("Search again and choose your stereo.")
    }
    busy = true
    epoch.operation += 1
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
    if device.infraredWake != nil, blaster(for: device) == nil, !defaults.bool(forKey: "infraredOfferSeen." + id) {
      defaults.set(id, forKey: Self.pendingOfferKey)
    } else {
      defaults.removeObject(forKey: Self.pendingOfferKey)
    }
  }

  func refresh() async {
    let version = epoch
    guard !busy, volumeStep == nil, refreshingEpoch != version, let state = receiver else { return }
    refreshingEpoch = version
    defer {
      if refreshingEpoch == version { refreshingEpoch = nil }
      if version == epoch, !Task.isCancelled, receiver?.connection == .connecting {
        receiver?.connection = .offline
      }
    }
    if state.online {
      let online = await HarmanNetwork.online(state.device)
      guard version == epoch, !Task.isCancelled else { return }
      if !online { disconnected() }
      return
    }
    guard let match = await identify(state.device, throttleDiscovery: true), version == epoch, !Task.isCancelled,
          await HarmanNetwork.online(match), version == epoch, !Task.isCancelled else { return }
    try? accept(match)
  }

  private func identify(_ saved: HKDevice, throttleDiscovery: Bool = false) async -> HKDevice? {
    let version = epoch
    if let url = saved.descriptionURL, let device = try? await HarmanNetwork.describe(url),
       device.id == saved.id, device.model == saved.model { return device }
    guard epoch == version, !Task.isCancelled else { return nil }
    // Check the saved address on every refresh. Only a search across the LAN needs a cooldown.
    if throttleDiscovery {
      let now = ContinuousClock.Instant.now
      guard now >= nextRediscovery else { return nil }
      nextRediscovery = now.advanced(by: .seconds(30))
    }
    return try? await discover().first { $0.id == saved.id && $0.model == saved.model }
  }

  @discardableResult func send(_ action: String, _ value: String? = nil) async -> Bool {
    guard !busy, let state = receiver, state.online || (action == "wake" && canWake) else { return false }
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
    epoch.operation += 1
    let version = epoch
    var message = "Command sent."
    do {
      if action == "wake", state.irWake, let ir = blaster(for: device) {
        if ir.kind == .itach { notify("Looking for your iTach. This can take a minute.") }
        let current = try await DirectInfrared.resolve(ir)
        try check(version)
        try await DirectInfrared.operate(current, send: true)
        message = "Infrared On signal sent."
      } else if action == "wake", let key = profile.keys["wake"] {
        // A sleeping receiver may answer its descriptor before it answers a heartbeat.
        // Reidentify an offline target before sending to a potentially reassigned address.
        let target = state.online ? device : await identify(device)
        try check(version)
        guard let target else { throw RemoteError("Couldn’t find this receiver on Wi-Fi to send Power on.") }
        _ = try await HarmanNetwork.transmit(target, packets: [profile.packet(key)])
        message = "Power on sent over Wi-Fi. Check the receiver."
      } else if action == "harman" || action == "set-mode" {
        guard state.actions.contains("harman"), let key = profile.keys["harman"] else { return false }
        let target = value.flatMap(HarmanVolume.Mode.init(rawValue:))
        guard action != "set-mode" || target != nil else { return false }
        message = try await changeHarmanVolume(to: action == "set-mode" ? target : nil, state: state,
                                               packet: profile.packet(key), version: version)
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
      }
      try check(version)
      if action == "standby" || action == "wake" {
        receiver?.lastSource = nil
        nextRediscovery = .now
      }
      if action != "louder" && action != "quieter" { pulse += 1; notify(message) }
      return true
    } catch {
      notify(error.localizedDescription)
      return false
    }
  }

  func syncHarmanVolume(_ mode: HarmanVolume.Mode, cycle: HarmanVolume.Cycle, for id: String) -> Bool {
    guard !busy, let state = receiver, state.online, state.device.id == id, state.actions.contains("harman") else { return false }
    let volume = HarmanVolume(mode: mode, cycle: cycle)
    volume.save(for: id, in: defaults)
    receiver?.harmanVolume = volume
    // The owner may have just pressed the physical button to read the display.
    nextHarmanPress = .now.advanced(by: Self.harmanPressInterval)
    pulse += 1
    notify("Tracking " + mode.rawValue + ".")
    return true
  }

  private func changeHarmanVolume(to target: HarmanVolume.Mode?, state: Receiver, packet: Data,
                                  version: ConnectionEpoch) async throws -> String {
    let id = state.device.id
    var volume = state.harmanVolume
    var presses = 1
    if let target {
      guard let current = volume.mode else { throw RemoteError("Sync the mode with the receiver display first.") }
      if current == target { return "Tracking " + current.rawValue + "." }
      presses = volume.cycle.next(after: current) == target ? 1 : 2
    }
    for _ in 0..<presses {
      try await Task.sleep(until: nextHarmanPress, clock: .continuous)
      try check(version)
      // A relaunch during the write must not restore the estimate from before this press.
      let pending = HarmanVolume(mode: nil, cycle: volume.cycle)
      pending.save(for: id, in: defaults)
      do {
        defer { nextHarmanPress = .now.advanced(by: Self.harmanPressInterval) }
        _ = try await HarmanNetwork.transmit(state.device, packets: [packet])
        try check(version)
      } catch {
        if receiver?.device.id == id { receiver?.harmanVolume = pending }
        throw RemoteError("Harman Volume press interrupted. Sync with the receiver display.")
      }
      volume.mode = volume.mode.map(volume.cycle.next)
      volume.save(for: id, in: defaults)
      receiver?.harmanVolume = volume
    }
    return volume.mode.map { "Tracking " + $0.rawValue + "." } ?? "Harman Volume cycle sent."
  }

  func configureInfrared(_ action: String, receiverId: String, id: String? = nil) async throws {
    guard !busy, volumeStep == nil, receiver?.infrared?.receiverId == receiverId,
          let device = receiver?.device, device.id == receiverId, let method = device.infraredWake else {
      throw RemoteError("Open infrared setup for the connected device again.")
    }
    busy = true
    defer { busy = false }
    epoch.operation += 1
    let version = epoch
    let key = "directIR." + device.id
    if action == "forget" {
      defaults.removeObject(forKey: key)
      receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "idle")
      return
    }
    guard blaster(for: device) == nil else { throw RemoteError("Forget the linked blaster before adding another one.") }
    let previous = receiver?.infrared
    do {
      var choice: LocalBlaster
      if action == "search" || action == "itach" {
        guard action != "itach" || method == .hk37xx else { throw RemoteError("Choose a BroadLink RM to learn Power On.") }
        receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "searching")
        let devices = try await discoverBlasters(action == "itach", method == .learnOn)
        try check(version)
        guard let first = devices.first else { throw RemoteError("No blasters found. Check the blaster’s power and Wi-Fi, then search again.") }
        if devices.count > 1 {
          receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "choose", devices: devices)
          return
        }
        choice = first
      } else if action == "select", previous?.phase == "choose", let candidate = previous?.devices?.first(where: { $0.id == id }) {
        choice = candidate
      } else if action == "learn", method == .learnOn, previous?.phase == "readyToLearn", let candidate = previous?.devices?.first {
        choice = candidate
      } else { throw RemoteError("Find your blaster again.") }
      if method == .learnOn {
        guard choice.kind == .broadlink else { throw RemoteError("Choose a BroadLink RM to learn Power On.") }
        if action != "learn" {
          receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "readyToLearn", devices: [choice])
          return
        }
        receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "preparing")
        choice.learnedOn = try await BroadLink.learnPowerOn(choice) {
          Task { @MainActor in
            guard self.epoch == version, self.receiver?.infrared?.phase == "preparing" else { return }
            self.receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "learning")
          }
        }
        choice.learnedForModel = device.model
      } else {
        receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "linking")
        try await DirectInfrared.operate(choice, send: false)
      }
      try check(version)
      defaults.set(try JSONEncoder().encode(choice), forKey: key)
      receiver?.infrared = InfraredStatus(receiverId: receiverId, phase: "linked", label: choice.label)
      finishInfraredOffer(for: receiverId)
    } catch {
      if version == epoch { receiver?.infrared = previous }
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
