import CommonCrypto
import Foundation

// Local BroadLink RM protocol as used by python-broadlink 0.19.0.
// Learning uses the same local session as sending a stored infrared signal.
enum BroadLink {
  private static let initialKey: [UInt8] = [9,118,40,52,63,233,158,35,118,92,21,19,172,207,139,2]
  private static let iv: [UInt8] = [86,46,23,153,109,9,61,40,221,179,186,105,90,46,111,88]
  private static let magic: [UInt8] = [0x5a,0xa5,0xaa,0x55,0x5a,0xa5,0xaa,0x55]
  private static let products: [Int: (String, Bool)] = {
    var result: [Int: (String, Bool)] = [:]
    func add(_ label: String, _ extended: Bool, _ types: [Int]) {
      for type in types { result[type] = (label, extended) }
    }
    add("RM mini 3", false, [0x2737,0x27b7,0x27c2,0x27c7,0x27cc,0x27cd,0x27d0,0x27d1,0x27d3,0x27dc,0x27de])
    add("RM mini", false, [0x278f])
    add("RM pro", false, [0x2712,0x272a,0x273d,0x277c,0x2783,0x2787,0x278b,0x2797,0x279d,0x27a1,0x27a6,0x27a9,0x27c3])
    add("RM mini 3", true, [0x5f36,0x6507,0x6508])
    add("RM4 mini", true, [0x51da,0x520c,0x520d,0x5216,0x6070,0x610e,0x62bc,0x6364,0x648d,0x653a])
    add("RM4C mini", true, [0x521c,0x610f,0x62be,0x6539])
    add("RM4 TV mate", true, [0x5209,0x5211,0x5212])
    add("RM4 pro", true, [0x520b,0x5213,0x6026,0x61a2,0x649b,0x653c])
    add("RM4C pro", true, [0x5218,0x6184])
    return result
  }()

  private static func word(_ bytes: [UInt8], _ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i+1]) << 8 }
  private static func put(_ n: Int, into bytes: inout [UInt8], at i: Int) {
    bytes[i] = UInt8(truncatingIfNeeded: n)
    bytes[i+1] = UInt8(truncatingIfNeeded: n >> 8)
  }
  private static func checksum(_ bytes: [UInt8]) -> Int { bytes.reduce(0xbeaf) { $0 + Int($1) } & 0xffff }

  static func hello(_ iface: HomeInterface, _ port: UInt16) -> Data {
    var b = [UInt8](repeating: 0, count: 48)
    let date = Date(), cal = Calendar(identifier: .gregorian)
    let offset = Int32(TimeZone.current.secondsFromGMT(for: date) / 3600)
    withUnsafeBytes(of: offset.littleEndian) { b.replaceSubrange(8..<12, with: $0) }
    let year = cal.component(.year, from: date)
    put(year, into: &b, at: 12)
    b[14...19] = [UInt8(cal.component(.minute, from: date)), UInt8(cal.component(.hour, from: date)),
                  UInt8(year % 100), UInt8((cal.component(.weekday, from: date) + 5) % 7 + 1),
                  UInt8(cal.component(.day, from: date)), UInt8(cal.component(.month, from: date))]
    b.replaceSubrange(24..<28, with: iface.host.split(separator: ".").compactMap { UInt8($0) }.reversed())
    put(Int(port), into: &b, at: 28)
    b[38] = 6
    put(checksum(b), into: &b, at: 32)
    return Data(b)
  }

  static func device(_ packet: Datagram) -> LocalBlaster? {
    let bytes = [UInt8](packet.bytes)
    guard bytes.count >= 128, let (model, _) = products[word(bytes, 52)] else { return nil }
    let mac = Array(bytes[58..<64].reversed())
    return LocalBlaster(id: "rm-" + mac.map { String(format: "%02x", $0) }.joined(), label: "BroadLink " + model,
                        kind: .broadlink, host: packet.host, port: packet.port, type: word(bytes, 52),
                        mac: mac, locked: bytes[127] != 0)
  }

  static func discover() async throws -> [LocalBlaster] {
    try await localNetworkTask {
      let packets: Set<Datagram>
      if LocalDiscovery.usesAnnouncements {
        packets = try LocalDiscovery.collect(port: 80) { [hello($0, $1)] }
      } else {
        packets = try LocalDiscovery.addressed(port: 80) { iface, port, _ in [hello(iface, port)] }
      }
      return packets.compactMap(device)
    }
  }

  private static func crypt(_ bytes: [UInt8], key: [UInt8], decrypt: Bool = false) throws -> [UInt8] {
    var output = [UInt8](repeating: 0, count: bytes.count + 16)
    let capacity = output.count
    var length = 0
    guard CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                  key, key.count, iv, bytes, bytes.count, &output, capacity, &length) == kCCSuccess else {
      throw RemoteError("Couldn’t read the blaster’s response.")
    }
    return Array(output.prefix(length))
  }

  private static func exchange(_ socket: LocalSocket, _ device: LocalBlaster, _ packet: Data) throws -> Datagram {
    try socket.datagram(packet, to: device.host, port: device.port)
    let deadline = LocalSocket.now + 1.5
    while socket.ready(POLLIN, until: deadline) {
      if let reply = socket.readDatagram(), reply.host == device.host && reply.port == device.port { return reply }
    }
    throw RemoteError("The blaster didn’t answer. Check its power and try again.")
  }

  private enum ReplyError: Error { case noSignal }

  private static func command(_ op: Int, body: [UInt8], device: LocalBlaster, key: [UInt8], session: [UInt8],
                              socket: LocalSocket, polling: Bool = false) throws -> [UInt8] {
    guard let mac = device.mac, let type = device.type else { throw RemoteError("Find your blaster again.") }
    var packet = [UInt8](repeating: 0, count: 56)
    packet.replaceSubrange(0..<8, with: magic)
    put(type, into: &packet, at: 36)
    put(op, into: &packet, at: 38)
    put(Int.random(in: 0x8000...0xffff), into: &packet, at: 40)
    packet.replaceSubrange(42..<48, with: mac.reversed())
    packet.replaceSubrange(48..<52, with: session)
    put(checksum(body), into: &packet, at: 52)
    let padded = body + [UInt8](repeating: 0, count: (16 - body.count % 16) % 16)
    packet += try crypt(padded, key: key)
    put(checksum(packet), into: &packet, at: 32)
    var reply = Array(try exchange(socket, device, Data(packet)).bytes)
    guard reply.count >= 56, reply.starts(with: magic) else { throw RemoteError("Unexpected blaster reply.") }
    let expected = word(reply, 32)
    put(0, into: &reply, at: 32)
    guard checksum(reply) == expected else { throw RemoteError("Invalid blaster reply.") }
    if polling, [0xfffb, 0xfff6].contains(word(reply, 34)) { throw ReplyError.noSignal }
    guard word(reply, 34) == 0 else {
      throw RemoteError("BroadLink declined local control. Turn off Lock device in the BroadLink app.")
    }
    return try crypt(Array(reply.dropFirst(56)), key: key, decrypt: true)
  }

  private struct Session {
    let socket: LocalSocket
    let device: LocalBlaster
    let key, id: [UInt8]
    let extended: Bool

    func request(_ action: UInt8, data: [UInt8] = []) throws -> [UInt8] {
      var payload = [action, 0, 0, 0] + data
      if extended {
        var size: [UInt8] = [0, 0]
        put(payload.count, into: &size, at: 0)
        payload = size + payload
      }
      return try command(0x6a, body: payload, device: device, key: key, session: id, socket: socket, polling: action == 4)
    }
  }

  private static func open(_ selected: LocalBlaster) throws -> Session {
    guard let iface = HomeInterface.all.first(where: { $0.contains(selected.host) }) else { throw RemoteError("Join your home Wi-Fi.") }
    let socket = try LocalSocket(type: SOCK_DGRAM, interface: iface)
    try socket.bind(iface.host)
    let reply = try exchange(socket, selected, hello(iface, socket.port))
    guard let current = device(reply), current.id == selected.id, let type = current.type else {
      throw RemoteError("The blaster moved. Find it again.")
    }
    guard current.locked != true else { throw RemoteError("Turn off Lock device for this blaster in the BroadLink app, then try again.") }
    var auth = [UInt8](repeating: 0, count: 80)
    auth.replaceSubrange(4..<20, with: repeatElement(0x31, count: 16))
    auth[30] = 1; auth[45] = 1
    auth.replaceSubrange(48..<54, with: "Test 1".utf8)
    let answer = try command(0x65, body: auth, device: current, key: initialKey, session: [0,0,0,0], socket: socket)
    guard answer.count >= 20 else { throw RemoteError("The blaster couldn’t authorize this iPhone.") }
    return Session(socket: socket, device: current, key: Array(answer[4..<20]),
                   id: Array(answer[0..<4]), extended: products[type]?.1 == true)
  }

  static func operate(_ selected: LocalBlaster, send: Bool) async throws {
    try await localNetworkTask {
      let session = try open(selected)
      if send {
        let waveform = selected.learnedOn.map { Array($0) } ?? InfraredSignal.broadLink
        try Task.checkCancellation()
        _ = try session.request(2, data: waveform)
      }
    }
  }

  static func validLearnedSignal(_ signal: Data) -> Bool {
    let header = Array(signal.prefix(4))
    return (8...4100).contains(signal.count) && header[0] == 0x26 && word(header, 2) == signal.count - 4
  }

  static func learnPowerOn(_ selected: LocalBlaster, listening: @escaping @Sendable () -> Void) async throws -> Data {
    try await localNetworkTask {
      let session = try open(selected)
      try Task.checkCancellation()
      _ = try session.request(3)
      listening()
      let deadline = LocalSocket.now + 25
      while LocalSocket.now < deadline {
        Thread.sleep(forTimeInterval: 0.4)
        try Task.checkCancellation()
        let reply: [UInt8]
        do { reply = try session.request(4) } catch ReplyError.noSignal { continue }
        let offset = session.extended ? 6 : 4
        guard reply.count >= offset + 4 else { continue }
        if session.extended {
          let size = word(reply, 0)
          guard size >= 8, size + 2 <= reply.count else { continue }
        }
        if reply[offset] == 0 { continue }
        let size = word(reply, offset + 2)
        let end = offset + 4 + size
        guard end <= reply.count, !session.extended || end <= word(reply, 0) + 2,
              validLearnedSignal(Data(reply[offset..<end])) else {
          throw RemoteError("Unexpected infrared signal. Try the receiver’s Power On button again.")
        }
        return Data(reply[offset..<end])
      }
      throw RemoteError("No signal received. Aim the handset at the blaster and try learning again.")
    }
  }
}
