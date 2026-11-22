import Foundation

struct RemoteError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

struct HKDevice: Codable, Identifiable {
  let id, host, model, name, profile: String
  var descriptionURL: URL?
  var renderer: URL?
  var advertised: Bool?

  var infraredWake: InfraredWakeMethod? {
    guard let entry = HarmanCatalog.shared.model(model), entry.profile == profile else { return nil }
    return entry.infraredWake
  }
}

enum InfraredWakeMethod: String, Decodable { case hk37xx, learnOn }

struct ReceiverInput: Codable {
  let id, name, detail: String
  var wire: String?
  var zone: String?
}

struct HarmanProfile: Decodable {
  let target, tag, agent: String
  let keys: [String: String]
  let sources: [ReceiverInput]

  func packet(_ key: String, value: String = "", zone: String = "Main Zone") -> Data {
    // All three fields come from the bundled catalogue or validated numeric speaker levels.
    let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><harman><\(tag)><common><control><name>\(key)</name><zone>\(zone)</zone><para>\(value)</para></control></common></\(tag)></harman>"
    return Data("POST \(target) HTTP/1.1\r\nHost: :10025\r\nUser-Agent: \(agent)\r\nContent-Length: \(xml.utf8.count)\r\n\r\n".utf8) + Data(xml.utf8)
  }

  func heartbeatReceived(_ bytes: Data) -> Bool {
    let xml = String(decoding: bytes, as: UTF8.self)
    let pattern = "<harman>\\s*<\(tag)>\\s*<common>\\s*<(status|control)>(.*?)</\\1>"
    guard let match = xml.captures(pattern), match[2].xmlValue("name") == "heart-alive" else { return false }
    return match[1].lowercased() == "status" ||
      (target == "AVR" && ["Main Zone", "Zone 2"].contains(match[2].xmlValue("zone")))
  }
}

struct HarmanCatalog: Decodable {
  struct Model: Decodable {
    let model, profile: String
    let infraredWake: InfraredWakeMethod?
  }
  let models: [String: Model]
  let profiles: [String: HarmanProfile]

  static let shared: Self = {
    // A missing catalogue is a build/packaging error.
    let url = Bundle.main.url(forResource: "receiver-profiles", withExtension: "json")!
    return try! JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }()

  func model(_ name: String) -> Model? {
    var key = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      .replacingOccurrences(of: #"^HARMAN[\s/.\-]*KARDON\s*"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"[\s-]"#, with: "", options: .regularExpression)
    if ["BDS280/80S","BDS580/80S"].contains(key) { key = String(key.prefix(6)) + "S" }
    if let exact = models[key] { return exact }
    if key.hasPrefix("HK"), let speaker = models[String(key.dropFirst(2))], speaker.profile == "mm" { return speaker }
    return nil
  }
}

extension String {
  func captures(_ pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
      let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
    return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
  }
  func xmlValue(_ tag: String) -> String {
    (captures("<" + tag + ">([^<]*)</" + tag + ">")?[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
