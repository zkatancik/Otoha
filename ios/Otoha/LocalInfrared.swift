import Darwin
import Foundation
import Security

struct LocalBlaster: Codable, Identifiable {
  enum Kind: String, Codable { case broadlink, irkit, remo, tasmota, itach, webhook }
  let id, label: String
  let kind: Kind
  let host: String
  let port: UInt16
  var type: Int?
  var mac: [UInt8]?
  var locked: Bool?
}

enum ManualIRWebhook {
  static func endpoint(_ value: String) throws -> URL {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    var address = in_addr()
    guard text.utf8.count <= 2048, !text.contains("\\"), !text.contains("#"),
          let url = URL(string: text, encodingInvalidCharacters: false),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host,
          inet_pton(AF_INET, host, &address) == 1, url.user == nil, url.password == nil,
          (1...65535).contains(url.port ?? 80) else { throw invalidAddress }
    let bits = UInt32(bigEndian: address.s_addr)
    guard bits >> 24 == 10 || bits >> 20 == 0xac1 || bits >> 16 == 0xc0a8 else { throw invalidAddress }
    return url
  }

  private static var invalidAddress: RemoteError {
    RemoteError("Copy the local Power On link from your blaster’s app and paste it here.")
  }

  private static func item(_ id: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Otoha.IRWebhook",
     kSecAttrAccount as String: id]
  }

  static func save(_ value: String, receiverId: String) throws -> LocalBlaster {
    let url = try endpoint(value)
    let query = item(receiverId)
    var entry = query
    entry[kSecValueData as String] = Data(url.absoluteString.utf8)
    entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    var result = SecItemAdd(entry as CFDictionary, nil)
    if result == errSecDuplicateItem {
      result = SecItemUpdate(query as CFDictionary, [kSecValueData: Data(url.absoluteString.utf8)] as CFDictionary)
    }
    guard result == errSecSuccess else { throw RemoteError("The webhook could not be saved on this iPhone.") }
    return LocalBlaster(id: receiverId, label: "Custom IR blaster", kind: .webhook,
                        host: url.host!, port: UInt16(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)))
  }

  static func forget(_ id: String) throws {
    let result = SecItemDelete(item(id) as CFDictionary)
    guard result == errSecSuccess || result == errSecItemNotFound else { throw RemoteError("The saved webhook could not be removed.") }
  }

  static func wake(_ id: String) async throws {
    var query = item(id)
    query[kSecReturnData as String] = true
    var stored: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &stored) == errSecSuccess,
          let data = stored as? Data, let text = String(data: data, encoding: .utf8) else {
      throw RemoteError("The webhook could not be read. Forget this blaster and link it again.")
    }
    try await LocalHTTP.postWebhook(endpoint(text))
  }
}

enum InfraredSignal {
  // HK 3770 discrete On: NEC1 device 128, subdevice 112, command 192.
  static let pulses: [Int] = {
    var result = [9024, 4512]
    for byte in [128, 112, 192, 63] {
      for bit in 0..<8 { result += [564, byte & (1 << bit) == 0 ? 564 : 1692] }
    }
    result.append(564)
    result.append(108000 - result.reduce(0, +))
    return result
  }()
  static let broadLink: [UInt8] = {
    var wave: [UInt8] = []
    for pulse in pulses {
      let ticks = Int(Double(pulse) / 32.84)
      if ticks > 255 { wave += [0, UInt8(ticks >> 8)] }
      wave.append(UInt8(truncatingIfNeeded: ticks))
    }
    return [0x26, 0, UInt8(truncatingIfNeeded: wave.count), UInt8(wave.count >> 8)] + wave
  }()
}

@MainActor private final class BonjourBlasters: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
  private static let services: [String: LocalBlaster.Kind] = ["_irkit._tcp.": .irkit, "_remo._tcp.": .remo, "_http._tcp.": .tasmota]
  private var browsers: [NetServiceBrowser] = []
  private var services: [NetService] = []
  private var results: [String: LocalBlaster] = [:]

  func search() async throws -> [LocalBlaster] {
    for type in Self.services.keys {
      let browser = NetServiceBrowser()
      browsers.append(browser)
      browser.delegate = self
      browser.searchForServices(ofType: type, inDomain: "local.")
    }
    defer {
      browsers.forEach { $0.stop() }
      services.forEach { $0.stop() }
    }
    try await Task.sleep(for: .seconds(3))
    return Array(results.values)
  }
  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    guard services.count < 96 else { return }
    services.append(service)
    service.delegate = self
    service.resolve(withTimeout: 2)
  }
  func netServiceDidResolveAddress(_ sender: NetService) {
    guard let kind = Self.services[sender.type], let port = UInt16(exactly: sender.port), port > 0 else { return }
    if kind == .tasmota {
      guard let txt = sender.txtRecordData(), NetService.dictionary(fromTXTRecord: txt)["devicetype"] == Data("tasmota".utf8) else { return }
    }
    for data in sender.addresses ?? [] where data.count >= MemoryLayout<sockaddr_in>.size {
      let address = data.withUnsafeBytes { $0.loadUnaligned(as: sockaddr_in.self) }
      guard address.sin_family == UInt8(AF_INET) else { continue }
      let host = dotted(address.sin_addr)
      guard HomeInterface.all.contains(where: { $0.contains(host) }) else { continue }
      let id = kind.rawValue + ":" + sender.name
      let family = kind == .irkit ? "IRKit" : (kind == .remo ? "Nature Remo" : "Tasmota IR")
      results[id] = LocalBlaster(id: id, label: family + " · " + sender.name, kind: kind, host: host, port: port)
      break
    }
  }
}

enum DirectInfrared {
  static func discover(itach: Bool = false) async throws -> [LocalBlaster] {
    if itach {
      guard LocalDiscovery.usesAnnouncements else {
        throw RemoteError("This version can’t discover an iTach. Choose another blaster in Power settings.")
      }
      return try await localNetworkTask {
        let packets = try LocalDiscovery.collect(group: "239.255.250.250", port: 9131, duration: 63) { _, _ in [] }
        return unique(packets.compactMap(beacon))
      }
    }
    async let rm = BroadLink.discover()
    async let bonjour = BonjourBlasters().search()
    let advertised = try await bonjour
    var devices: [LocalBlaster] = []
    for device in advertised {
      if device.kind != .tasmota { devices.append(device) }
      else if (try? await http(device, send: false)) != nil { devices.append(device) }
    }
    do { devices += try await rm } catch { if devices.isEmpty { throw error } }
    return unique(devices)
  }

  private static func unique(_ devices: [LocalBlaster]) -> [LocalBlaster] {
    var ids = Set<String>()
    return devices.sorted { ($0.label, $0.id) < ($1.label, $1.id) }.filter { ids.insert($0.id).inserted }
  }
  private static func beacon(_ packet: Datagram) -> LocalBlaster? {
    let text = String(decoding: packet.bytes, as: UTF8.self)
    guard text.hasPrefix("AMXB"), text.contains("<-Make=GlobalCache>"),
      let mac = text.captures(#"<-UUID=GlobalCache_([0-9a-f]{12})>"#)?[1],
      let model = text.captures(#"<-Model=([^>]+)>"#)?[1],
      ["itachip2ir","itachwf2ir","itachflexethernet","itachflexethernetpoe","itachflexwifi"].contains(model.lowercased())
    else { return nil }
    return LocalBlaster(id: "itach-" + mac.lowercased(), label: "Global Caché " + model, kind: .itach,
                        host: packet.host, port: 4998)
  }

  static func operate(_ device: LocalBlaster, send: Bool) async throws {
    switch device.kind {
    case .webhook:
      if send { try await ManualIRWebhook.wake(device.id) }
    case .broadlink: try await BroadLink.operate(device, send: send)
    case .itach:
      try await Task.detached {
        let socket = try LocalSocket.connect(to: device.host, port: device.port, until: LocalSocket.now + 2)
        func exchange(_ command: String) throws -> String {
          let end = LocalSocket.now + 2
          try socket.write(Data((command + "\r").utf8), until: end)
          return String(decoding: socket.read(until: end) { $0.contains(13) }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let mode = try exchange("get_IR,1:1")
        guard ["IR","IR_BLASTER","IRTRIPORT","IRTRIPORT_BLASTER"].contains(where: { mode == "IR,1:1," + $0 }) else {
          throw RemoteError("Connect the emitter to output 1 and set it to IR.")
        }
        if send {
          let cycles = InfraredSignal.pulses.map { String(Int((Double($0) * 0.038).rounded())) }.joined(separator: ",")
          guard try exchange("sendir,1:1,1,38000,1,1," + cycles) == "completeir,1:1,1" else {
            throw RemoteError("The blaster didn’t confirm the On signal.")
          }
        }
      }.value
    case .irkit, .remo, .tasmota: try await http(device, send: send)
    }
  }

  // Resolve the saved identity on this Wi-Fi before sending any IR, even after a DHCP change.
  static func resolve(_ device: LocalBlaster) async throws -> LocalBlaster {
    let found: [LocalBlaster]
    switch device.kind {
    case .webhook: return device
    case .broadlink: found = try await BroadLink.discover()
    case .itach: found = try await discover(itach: true)
    default: found = try await BonjourBlasters().search()
    }
    guard let current = found.first(where: { $0.id == device.id }) else { throw RemoteError("Your linked blaster wasn’t found. Check its power and Wi-Fi.") }
    return current
  }

  private static func http(_ device: LocalBlaster, send: Bool) async throws {
    guard let base = URL(string: "http://\(device.host):\(device.port)") else { throw RemoteError("Find the blaster again.") }
    if device.kind == .tasmota {
      func command(_ text: String) async throws -> [String: Any] {
        var url = URLComponents(url: base.appendingPathComponent("cm"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "cmnd", value: text)]
        let bytes = try await LocalHTTP.fetch(URLRequest(url: url.url!))
        return try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
      }
      let pins = try await command("GPIO 255")
      guard pins.contains(where: { key, value in
        key.range(of: #"^GPIO\d+$"#, options: .regularExpression) != nil &&
          String(describing: value).range(of: #"\bIRsend\b"#, options: [.regularExpression,.caseInsensitive]) != nil
      }) else { throw RemoteError("This Tasmota needs an IRsend output.") }
      if send {
        let response = try await command(#"IRSend {"Protocol":"NEC","Bits":32,"Data":"0x010E03FC","Repeat":0}"#)
        guard response.contains(where: { $0.key.lowercased() == "irsend" && ($0.value as? String)?.lowercased() == "done" }) else { throw RemoteError("Tasmota declined the On signal.") }
      }
    } else if send {
      let pulses = InfraredSignal.pulses.dropLast().map { device.kind == .irkit ? $0 * 2 : $0 }
      var request = URLRequest(url: base.appendingPathComponent("messages"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Otoha", forHTTPHeaderField: "X-Requested-With")
      request.httpBody = try JSONSerialization.data(withJSONObject: ["format": device.kind == .irkit ? "raw" : "us", "freq": 38, "data": pulses])
      _ = try await LocalHTTP.fetch(request)
    } else {
      // Reading /messages would consume a learned code. A TCP connection is sufficient here.
      _ = try await Task.detached { try LocalSocket.connect(to: device.host, port: device.port, until: LocalSocket.now + 2) }.value
    }
  }
}
