import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum LocalHTTP {
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.allowsCellularAccess = false
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.httpShouldSetCookies = false
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 3
    return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
  }()

  static func allowed(_ url: URL, host: String) -> Bool {
    url.scheme == "http" && url.host == host && url.user == nil && url.password == nil &&
      HomeInterface.all.contains { $0.contains(host) }
  }

  static func fetch(_ request: URLRequest) async throws -> Data {
    guard let url = request.url, let host = url.host, allowed(url, host: host) else {
      throw RemoteError("Reconnect to your home Wi-Fi.")
    }
    let (stream, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw RemoteError("The device declined the request.")
    }
    var data = Data()
    for try await byte in stream {
      guard data.count < 65536 else { throw RemoteError("The device sent an unexpected response.") }
      data.append(byte)
    }
    return data
  }
}

private final class DeviceDescription: NSObject, XMLParserDelegate {
  var fields: [String: String] = [:]
  var rendererPath: String?
  private var stack: [String] = []
  private var content = ""
  private var service: [String: String] = [:]
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
              qualifiedName qName: String?, attributes attributeDict: [String: String]) {
    stack.append(elementName)
    content = ""
    if elementName == "service" { service = [:] }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { content += string }
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if stack.count == 3 && stack.dropLast().last == "device" { fields[elementName] = value }
    if stack.dropLast().last == "service" { service[elementName] = value }
    if elementName == "service", service["serviceType"] == "urn:schemas-upnp-org:service:RenderingControl:1" {
      rendererPath = service["controlURL"]
    }
    _ = stack.popLast()
    content = ""
  }
}

enum HarmanNetwork {
  static func describe(_ url: URL) async throws -> HKDevice {
    let data = try await LocalHTTP.fetch(URLRequest(url: url))
    let parser = XMLParser(data: data)
    let xml = DeviceDescription()
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = xml
    guard parser.parse(), let host = url.host, let maker = xml.fields["manufacturer"],
      maker.range(of: #"^harman[\s/.-]*kardon(?:\s+international(?: industries)?(?:,? inc\.?)?)?$"#,
                  options: [.regularExpression, .caseInsensitive]) != nil,
      let id = xml.fields["UDN"], !id.isEmpty, id.count <= 200 else { throw RemoteError("Unrecognized stereo.") }
    let label = xml.fields["friendlyName"] ?? ""
    let modelName = xml.fields["modelName"] ?? ""
    let name = modelName.isEmpty || modelName.lowercased() == "none" ? label : modelName
    guard let model = HarmanCatalog.shared.model(name) else { throw RemoteError("This stereo is not supported.") }
    let renderer = xml.rendererPath.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
    return HKDevice(id: id, host: host, model: model.model, name: label.isEmpty ? model.model : String(label.prefix(96)),
                    profile: model.profile, descriptionURL: url,
                    renderer: renderer.flatMap { LocalHTTP.allowed($0, host: host) && $0.port == url.port ? $0 : nil })
  }

  static func advertisement(_ packet: Datagram) -> (URL, HKDevice?)? {
    let lines = String(decoding: packet.bytes, as: UTF8.self).components(separatedBy: .newlines)
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      let parts = line.split(separator: ":", maxSplits: 1)
      if parts.count == 2 { headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
    }
    let first = lines.first?.uppercased() ?? ""
    guard first.hasPrefix("HTTP/1.1 200") || first.hasPrefix("HTTP/1.0 200") ||
            (first.hasPrefix("NOTIFY * HTTP/1.1") && headers["nts"]?.lowercased() == "ssdp:alive"),
          let url = headers["location"].flatMap(URL.init(string:)), LocalHTTP.allowed(url, host: packet.host) else { return nil }
    let server = headers["server"] ?? ""
    guard let raw = server.captures(#"^Harman Kardon (BDS (?:G3|235|535|280S?|580S?))(?=\s|/|$)"#)?[1],
          let id = headers["usn"]?.components(separatedBy: "::").first, id.hasPrefix("uuid:"), id.count <= 200 else { return (url, nil) }
    let sModel = ["BDS 280", "BDS 580"].contains(raw.uppercased()) && server.lowercased().contains("/80s")
    guard let model = HarmanCatalog.shared.model(raw + (sModel ? "S" : "")) else { return (url, nil) }
    return (url, HKDevice(id: id, host: packet.host, model: model.model, name: model.model, profile: model.profile, advertised: true))
  }

  static func discover() async throws -> [HKDevice] {
    let targets = ["harman-com:service:remote-controller:1", "urn:schemas-upnp-org:device:MediaRenderer:1",
                   "upnp:rootdevice", "\"upnp:rootdevice\"", "upnp:all"]
    @Sendable func query(_ target: String, host: String) -> Data {
      Data("M-SEARCH * HTTP/1.1\r\nHOST: \(host):1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(target)\r\n\r\n".utf8)
    }
    let packets = try await localNetworkTask {
      if LocalDiscovery.usesAnnouncements {
        let messages = targets.map { query($0, host: "239.255.255.250") }
        return try LocalDiscovery.collect(group: "239.255.255.250", port: 1900) { _, _ in messages }
      }
      return try LocalDiscovery.addressed(port: 1900) { _, _, host in
        [query("ssdp:all", host: host), query("harman-com:service:remote-controller:1", host: host)]
      }
    }
    try Task.checkCancellation()
    let entries = packets.compactMap(advertisement)
    var devices = entries.compactMap(\.1)
    var urls = Set(entries.filter { $0.1 == nil || $0.0.port != 10025 }.map(\.0)).prefix(64).makeIterator()
    await withTaskGroup(of: HKDevice?.self) { group in
      for _ in 0..<8 {
        if let url = urls.next() { group.addTask { try? await describe(url) } }
      }
      for await device in group {
        if let device { devices.append(device) }
        if let url = urls.next() { group.addTask { try? await describe(url) } }
      }
    }
    var ids = Set<String>(), hosts = Set<String>()
    return devices.sorted { ($0.renderer != nil ? 2 : ($0.advertised == true ? 0 : 1)) >
                            ($1.renderer != nil ? 2 : ($1.advertised == true ? 0 : 1)) }
      .filter { device in
        guard !ids.contains(device.id), !hosts.contains(device.host) else { return false }
        ids.insert(device.id); hosts.insert(device.host)
        return true
      }
      .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
  }

  static func transmit(_ device: HKDevice, packets: [Data], heartbeat: Bool = false) async throws -> Data {
    guard let profile = HarmanCatalog.shared.profiles[device.profile] else { throw RemoteError("Unsupported stereo.") }
    return try await Task.detached {
      let end = LocalSocket.now + 1.7
      let socket = try LocalSocket.connect(to: device.host, port: 10025, until: end)
      for (index, data) in packets.enumerated() {
        if index > 0 { try await Task.sleep(for: .milliseconds(50)) }
        try socket.write(data, until: end)
      }
      return heartbeat ? socket.read(until: end, complete: profile.heartbeatReceived) : Data()
    }.value
  }

  static func online(_ device: HKDevice) async -> Bool {
    guard let profile = HarmanCatalog.shared.profiles[device.profile],
          let reply = try? await transmit(device, packets: [profile.packet("heart-alive", zone: "")], heartbeat: true) else { return false }
    if profile.heartbeatReceived(reply) { return true }
    guard reply.isEmpty else { return false }
    if ["AVR 170", "AVR 1700", "AVR 170/1700", "AVR 170/230C"].contains(device.model) { return true }
    guard ["stereo", "mm"].contains(device.profile), let url = device.renderer else { return false }
    let type = "urn:schemas-upnp-org:service:RenderingControl:1"
    for (action, field) in [("GetVolume", "CurrentVolume"), ("GetMute", "CurrentMute")] {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.setValue("\"\(type)#\(action)\"", forHTTPHeaderField: "SOAPAction")
      request.httpBody = Data("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:\(action) xmlns:u=\"\(type)\"><InstanceID>0</InstanceID><Channel>Master</Channel></u:\(action)></s:Body></s:Envelope>".utf8)
      if let bytes = try? await LocalHTTP.fetch(request) {
        let response = String(decoding: bytes, as: UTF8.self)
        if response.contains(action + "Response"), let value = Int(response.xmlValue(field)),
           (0...(action == "GetMute" ? 1 : 100)).contains(value) { return true }
      }
    }
    return false
  }
}
