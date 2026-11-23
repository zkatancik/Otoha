import Foundation

@main struct DirectRemoteCheck {
  @MainActor static func main() async throws {
    if CommandLine.arguments[1] == "--read-saved-mode" {
      let prefs = UserDefaults(suiteName: CommandLine.arguments[2])!
      let reopened = Remote(defaults: prefs)
      precondition(reopened.receiver?.device.id == CommandLine.arguments[3])
      precondition(reopened.receiver?.harmanVolume.mode?.rawValue == CommandLine.arguments[4])
      return
    }
    let host = CommandLine.arguments[1], port = UInt16(CommandLine.arguments[2])!
    let location = URL(string: "http://\(host):\(port)/device.xml")!
    let packet = Datagram(host: host, port: 1900, bytes: Data("HTTP/1.1 200 OK\r\nLOCATION: \(location)\r\n\r\n".utf8))
    let suite = "OtohaTest." + UUID().uuidString
    let prefs = UserDefaults(suiteName: suite)!
    defer { prefs.removePersistentDomain(forName: suite) }
    let search: () async throws -> [HKDevice] = {
      guard let (url, _) = HarmanNetwork.advertisement(packet) else { fatalError("Missing advertisement") }
      return [try await HarmanNetwork.describe(url)]
    }
    var interruptFirstSearch: (() -> Void)?
    var searches = 0
    let remote = Remote(defaults: prefs, discover: {
      searches += 1
      if let interrupt = interruptFirstSearch {
        interruptFirstSearch = nil
        interrupt()
        return [HKDevice(id: "uuid:old-network", host: host, model: "HK 3770", name: "Old stereo", profile: "stereo")]
      }
      return try await search()
    })
    interruptFirstSearch = { remote.networkPathChanged() }
    let devices = try await remote.locateDevices()
    precondition(devices.count == 1 && devices[0].name == "Test & Stereo")
    precondition(remote.receiver == nil && !remote.hasPendingInfraredOffer)
    do {
      try await remote.linkDevice("unselected-id")
      fatalError("Unexpected connection")
    } catch is RemoteError { }
    precondition(remote.receiver == nil && !remote.hasPendingInfraredOffer)
    try await remote.linkDevice(devices[0].id)
    precondition(remote.hasPendingInfraredOffer)
    precondition(remote.receiver?.online == true && remote.receiver?.infrared?.phase == "idle")
    precondition(remote.receiver?.harmanVolume.mode == nil)
    precondition(remote.syncHarmanVolume(.off, cycle: .highFirst, for: devices[0].id))
    let steps = [("louder", nil), ("source", "usb"), ("set-mode", "Off"), ("set-mode", "Low")]
    for (action, value) in steps {
      let sent = await remote.send(action, value)
      precondition(sent, "Failed to send " + action)
    }
    precondition(remote.receiver?.harmanVolume.mode == .low && remote.receiver?.lastSource == "usb")
    let tappedAgain = await remote.send("set-mode", "Off")
    precondition(tappedAgain)
    let powerState = URL(fileURLWithPath: CommandLine.arguments[5])
    func waitForDisplay(_ mode: String, at name: String = "display") async throws {
      let display = powerState.deletingLastPathComponent().appendingPathComponent(name)
      let deadline = ContinuousClock.now.advanced(by: .seconds(1))
      while try String(contentsOf: display, encoding: .utf8) != mode {
        precondition(ContinuousClock.now < deadline, "Receiver missed a Harman Volume press; expected " + mode)
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    try await waitForDisplay("Off")
    precondition(Remote(defaults: prefs, discover: search).receiver?.harmanVolume.mode == .off,
                 "Reopening the app lost the synced Harman Volume mode")
    func setPowerState(_ state: String) throws {
      try Data(state.utf8).write(to: powerState, options: .atomic)
    }
    try setPowerState("off")
    await remote.refresh()
    precondition(remote.receiver?.online == false)
    await remote.refresh()
    let searchesWhileOff = searches
    await remote.refresh()
    precondition(searches == searchesWhileOff, "Repeated a network-wide search during standby")
    try setPowerState("other")
    await remote.refresh()
    precondition(remote.receiver?.online == false, "Reconnected to another stereo at the saved address")
    try setPowerState("booting")
    await remote.refresh()
    precondition(remote.receiver?.online == false, "Reconnected before the control service was ready")
    try setPowerState("on")
    await remote.refresh()
    precondition(remote.receiver?.online == true, "The open remote stayed offline after the receiver powered back on")
    precondition(searches == searchesWhileOff && remote.receiver?.device.id == devices[0].id)
    let controlsRestored = await remote.send("quieter")
    precondition(controlsRestored)
    let restarted = Remote(defaults: prefs, discover: search)
    precondition(restarted.receiver?.online == false && restarted.receiver?.harmanVolume.mode == .off)
    precondition(restarted.canWake)
    let woke = await restarted.send("wake")
    precondition(woke && restarted.receiver?.online == false)
    await restarted.refresh()
    precondition(restarted.receiver?.online == true && restarted.receiver?.device.id == devices[0].id)
    precondition(restarted.receiver?.harmanVolume.mode == .off)

    let fixture = LocalBlaster(id: "rm-001122334455", label: "BroadLink RM mini 3", kind: .broadlink,
                              host: host, port: UInt16(CommandLine.arguments[3])!, type: 0x2737,
                              mac: [0,17,34,51,68,85], locked: false)
    try await BroadLink.operate(fixture, send: false)
    try await BroadLink.operate(fixture, send: true)

    restarted.finishInfraredOffer(for: devices[0].id)
    _ = try await restarted.locateDevices()
    try await restarted.linkDevice(devices[0].id)
    precondition(!restarted.hasPendingInfraredOffer)
    precondition(restarted.receiver?.harmanVolume.mode == .off)

    // On the owner's HK 3770, one press from High goes to Off, then Low, then High.
    try setPowerState("other")
    let other = try await restarted.locateDevices()[0]
    try await restarted.linkDevice(other.id)
    precondition(other.id != devices[0].id && restarted.receiver?.harmanVolume.mode == nil)
    guard let defaultCycle = restarted.receiver?.harmanVolume.cycle else { fatalError("Missing linked receiver") }
    precondition(defaultCycle.modes == [.high, .off, .low], "Buttons must follow the observed HK 3770 cycle")
    precondition(restarted.syncHarmanVolume(.high, cycle: defaultCycle, for: other.id))
    let selectedOff = await restarted.send("set-mode", "Off")
    precondition(selectedOff && restarted.receiver?.harmanVolume.mode == .off)
    try await waitForDisplay("Off", at: "other-display")
    let cycled = await restarted.send("harman")
    precondition(cycled && restarted.receiver?.harmanVolume.mode == .low)
    try await waitForDisplay("Low", at: "other-display")
    let cycledBack = await restarted.send("set-mode", "High")
    precondition(cycledBack)
    try await waitForDisplay("High", at: "other-display")
    let otherReopened = Remote(defaults: prefs, discover: search)
    precondition(otherReopened.receiver?.harmanVolume.mode == .high && otherReopened.receiver?.harmanVolume.cycle == .lowFirst)
    try setPowerState("on")
    _ = try await restarted.locateDevices()
    try await restarted.linkDevice(devices[0].id)
    precondition(restarted.receiver?.harmanVolume.mode == .off && restarted.receiver?.harmanVolume.cycle == .highFirst)

    // Background between two writes. The first press is the last completed step.
    let changing = Task { await restarted.send("set-mode", "Low") }
    for _ in 0..<200 where restarted.receiver?.harmanVolume.mode != .high {
      try await Task.sleep(for: .milliseconds(10))
    }
    restarted.disconnected()
    let completed = await changing.value
    precondition(!completed && restarted.receiver?.harmanVolume.mode == .high)
    try await waitForDisplay("High")
    let freshProcess = Process()
    freshProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    freshProcess.arguments = ["--read-saved-mode", suite, devices[0].id, "High"]
    try freshProcess.run()
    freshProcess.waitUntilExit()
    precondition(freshProcess.terminationStatus == 0, "A fresh process lost the completed press")
    await restarted.refresh()
    precondition(restarted.receiver?.online == true && restarted.receiver?.harmanVolume.mode == .high)

    let signal = Data([0x26, 0, 6, 0, 0x10, 0x11, 0x20, 0x21, 0x40, 0x41])
    var mini = fixture
    mini.learnedOn = try await BroadLink.learnPowerOn(fixture) {}
    precondition(mini.learnedOn == signal)
    try await BroadLink.operate(mini, send: true)

    let rm4 = LocalBlaster(id: "rm-0123456789ab", label: "BroadLink RM4 mini", kind: .broadlink,
                           host: host, port: UInt16(CommandLine.arguments[4])!, type: 0x51da,
                           mac: [1,35,69,103,137,171], locked: false)
    let avrURL = location.deletingLastPathComponent().appendingPathComponent("avr.xml")
    let avr = Remote(defaults: prefs, discover: { [try await HarmanNetwork.describe(avrURL)] },
                     discoverBlasters: { itach, learning in
                       precondition(!itach && learning)
                       return [fixture, rm4]
                     })
    let avrID = try await avr.locateDevices()[0].id
    try await avr.linkDevice(avrID)
    precondition(avr.hasPendingInfraredOffer)
    try await avr.configureInfrared("search", receiverId: avrID)
    precondition(avr.receiver?.infrared?.phase == "choose")
    try await avr.configureInfrared("select", receiverId: avrID, id: rm4.id)
    precondition(avr.receiver?.infrared?.phase == "readyToLearn")
    do {
      try await avr.configureInfrared("learn", receiverId: avrID)
      fatalError("Saved a non-IR capture")
    } catch is RemoteError { }
    precondition(avr.receiver?.infrared?.phase == "readyToLearn" && prefs.data(forKey: "directIR." + avrID) == nil)
    try await avr.configureInfrared("learn", receiverId: avrID)
    precondition(avr.receiver?.irWake == true && !avr.hasPendingInfraredOffer)
    let restored = Remote(defaults: prefs, discover: search)
    precondition(restored.receiver?.irWake == true && restored.receiver?.online == false)
    let binding = try JSONDecoder().decode(LocalBlaster.self, from: prefs.data(forKey: "directIR." + avrID)!)
    precondition(binding.id == rm4.id && binding.learnedOn == signal && binding.learnedForModel == "AVR 170")
    try await BroadLink.operate(binding, send: true)
    try await restored.configureInfrared("forget", receiverId: avrID)
    precondition(restored.receiver?.irWake == false && !restored.hasPendingInfraredOffer)

    let storedID = "uuid:saved-receiver"
    let presetModels = ["HK 3700", "HK 3770"]
    let learnModels = ["AVR 151S", "AVR 1510S", "AVR 170", "AVR 1700", "AVR 370", "AVR 3700"]
    for (key, model) in HarmanCatalog.shared.models {
      let saved = HKDevice(id: storedID, host: host, model: model.model, name: "Saved receiver",
                           profile: model.profile, descriptionURL: location)
      prefs.set(try JSONEncoder().encode(saved), forKey: "directReceiver.v1")
      let family = String(model.model.split(separator: "/")[0])
      let preset = presetModels.contains(family)
      let learning = learnModels.contains(family)
      precondition(HarmanCatalog.shared.model(key)?.infraredWake == saved.infraredWake, key)
      for candidate in [fixture, binding] {
        prefs.set(try JSONEncoder().encode(candidate), forKey: "directIR." + storedID)
        let savedRemote = Remote(defaults: prefs, discover: search)
        precondition((savedRemote.receiver?.infrared != nil) == (preset || learning), key)
        let linked = (preset && candidate.learnedOn == nil) || (learning && candidate.learnedForModel == saved.model)
        precondition(savedRemote.receiver?.irWake == linked && !savedRemote.hasPendingInfraredOffer, key)
        precondition(savedRemote.canWake == (model.profile != "mm"), key)
        if !preset && !learning {
          do {
            try await savedRemote.configureInfrared("forget", receiverId: storedID)
            fatalError("Unexpected infrared setup for " + key)
          } catch is RemoteError { }
        }
        if saved.model == "AVR 270", candidate.learnedOn == nil {
          let sent = await savedRemote.send("wake")
          precondition(!sent, "The receiver at the saved address has a different identity.")
        }
      }
    }
    _ = try await restarted.locateDevices()
    try await restarted.linkDevice(devices[0].id)
    let unplug = location.deletingLastPathComponent().appendingPathComponent("unplug-control")
    _ = try await LocalHTTP.fetch(URLRequest(url: unplug))
    let failed = await restarted.send("set-mode", "Low")
    precondition(!failed && restarted.receiver?.harmanVolume.mode == nil)
    let afterFailure = Remote(defaults: prefs)
    precondition(afterFailure.receiver?.device.id == devices[0].id && afterFailure.receiver?.harmanVolume.mode == nil)
    print("Verified Harman Volume pacing, sync, relaunch, interrupted writes, receiver reconnection and BroadLink control.")
  }
}
