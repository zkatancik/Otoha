import Foundation

@main struct DirectRemoteCheck {
  @MainActor static func main() async throws {
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
    let remote = Remote(defaults: prefs, discover: search)
    let devices = try await remote.locateDevices()
    precondition(devices.count == 1 && devices[0].name == "Test & Stereo")
    try await remote.linkDevice(devices[0].id)
    precondition(remote.receiver?.online == true && remote.receiver?.infrared?.phase == "idle")
    let steps = [("louder", nil), ("source", "usb"), ("sync-mode", "Off"), ("set-mode", "Low")]
    for (action, value) in steps {
      let sent = await remote.send(action, value)
      precondition(sent, "Failed to send " + action)
    }
    precondition(remote.receiver?.trackedMode == "Low" && remote.receiver?.lastSource == "usb")
    let restarted = Remote(defaults: prefs, discover: search)
    precondition(restarted.receiver?.online == false && restarted.receiver?.trackedMode == nil)
    precondition(restarted.canWake)
    let woke = await restarted.send("wake")
    precondition(woke && restarted.receiver?.online == false)
    await restarted.refresh()
    precondition(restarted.receiver?.online == true && restarted.receiver?.device.id == devices[0].id)

    let fixture = LocalBlaster(id: "rm-001122334455", label: "BroadLink RM mini 3", kind: .broadlink,
                              host: host, port: UInt16(CommandLine.arguments[3])!, type: 0x2737,
                              mac: [0,17,34,51,68,85], locked: false)
    try await BroadLink.operate(fixture, send: false)
    try await BroadLink.operate(fixture, send: true)

    // Even an old blaster link must never enable the HK 3770 preset on a different model.
    let storedID = "uuid:saved-receiver"
    prefs.set(try JSONEncoder().encode(fixture), forKey: "directIR." + storedID)
    for model in HarmanCatalog.shared.models.values {
      let saved = HKDevice(id: storedID, host: host, model: model.model, name: "Saved receiver",
                           profile: model.profile, descriptionURL: location)
      prefs.set(try JSONEncoder().encode(saved), forKey: "directReceiver.v1")
      let savedRemote = Remote(defaults: prefs, discover: search)
      let eligible = model.model == "HK 3770"
      precondition((savedRemote.receiver?.infrared != nil) == eligible, model.model)
      precondition(savedRemote.receiver?.irWake == eligible, model.model)
      precondition(savedRemote.canWake == (model.profile != "mm"), model.model)
      if !eligible {
        do {
          try await savedRemote.configureInfrared("forget", receiverId: storedID)
          fatalError("Unexpected infrared setup for " + model.model)
        } catch is RemoteError { }
      }
      if model.model == "HK 3700" {
        let sent = await savedRemote.send("wake")
        precondition(!sent, "The receiver at the saved address has a different identity.")
      }
    }
    print("Verified direct commands, network wake, identity checks, and infrared eligibility across the catalog.")
  }
}
