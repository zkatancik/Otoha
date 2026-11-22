import Darwin
import Foundation

func dotted(_ value: in_addr) -> String {
  var ip = value
  var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
  inet_ntop(AF_INET, &ip, &buffer, socklen_t(buffer.count))
  return String(cString: buffer)
}

private func ipv4(_ host: String, _ port: UInt16) -> sockaddr_in {
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = port.bigEndian
  inet_pton(AF_INET, host, &address.sin_addr)
  return address
}

private func withAddress<T>(_ address: inout sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
  withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
  }
}

struct HomeInterface {
  let ip, mask: in_addr
  let index: UInt32
  var host: String { dotted(ip) }
  var broadcast: String { dotted(in_addr(s_addr: ip.s_addr | ~mask.s_addr)) }

  func contains(_ host: String) -> Bool {
    var peer = in_addr()
    guard inet_pton(AF_INET, host, &peer) == 1 else { return false }
    return (peer.s_addr & mask.s_addr) == (ip.s_addr & mask.s_addr)
      && host != broadcast && peer.s_addr != (ip.s_addr & mask.s_addr)
  }

  static var all: [Self] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0 else { return [] }
    defer { freeifaddrs(head) }
    var result: [Self] = []
    var cursor = head
    while let node = cursor {
      let item = node.pointee
      cursor = item.ifa_next
      let flags = Int32(item.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
        item.ifa_addr?.pointee.sa_family == UInt8(AF_INET), let mask = item.ifa_netmask else { continue }
      let ip = UnsafeRawPointer(item.ifa_addr!).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
      result.append(Self(ip: ip, mask: UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr,
                         index: if_nametoindex(item.ifa_name)))
    }
    return result
  }
}

struct Datagram: Hashable {
  let host: String
  let port: UInt16
  let bytes: Data
}

// These bounded socket operations run off the UI thread. Each descriptor is bound to its LAN interface.
final class LocalSocket {
  let fd: Int32
  init(type: Int32, interface: HomeInterface? = nil) throws {
    let socket = Darwin.socket(AF_INET, type, 0)
    guard socket >= 0 else { throw RemoteError("The phone couldn’t open a local connection.") }
    fd = socket
    if var index = interface?.index, setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, 4) != 0 {
      throw RemoteError("The Wi-Fi connection changed. Try again.")
    }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, 4)
    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
  }
  deinit { Darwin.close(fd) }

  static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  func ready(_ events: Int32, until end: TimeInterval) -> Bool {
    var entry = pollfd(fd: fd, events: Int16(events), revents: 0)
    while Self.now < end {
      let result = poll(&entry, 1, Int32(max(1, (end - Self.now) * 1000)))
      if result >= 0 { return result > 0 }
      if errno != EINTR { return false }
    }
    return false
  }

  func bind(_ host: String, port: UInt16 = 0) throws {
    var address = ipv4(host, port)
    guard withAddress(&address, { Darwin.bind(fd, $0, $1) }) == 0 else {
      throw RemoteError("Allow Local Network access for Otoha, then search again.")
    }
  }

  var port: UInt16 {
    var address = sockaddr_in()
    var size = socklen_t(MemoryLayout.size(ofValue: address))
    withUnsafeMutablePointer(to: &address) {
      _ = $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
    }
    return UInt16(bigEndian: address.sin_port)
  }

  func datagram(_ bytes: Data, to host: String, port: UInt16) throws {
    var dest = ipv4(host, port)
    let sent = withAddress(&dest) { address, size in
      bytes.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, address, size) }
    }
    guard sent == bytes.count else { throw RemoteError("Join your home Wi-Fi and allow Local Network access for Otoha in Settings.") }
  }

  func readDatagram() -> Datagram? {
    var peer = sockaddr_in()
    var size = socklen_t(MemoryLayout.size(ofValue: peer))
    var buffer = [UInt8](repeating: 0, count: 8192)
    let count = withUnsafeMutablePointer(to: &peer) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &size) }
    }
    guard count > 0 else { return nil }
    return Datagram(host: dotted(peer.sin_addr), port: UInt16(bigEndian: peer.sin_port),
                    bytes: Data(buffer.prefix(count)))
  }

  static func connect(to host: String, port: UInt16, until end: TimeInterval) throws -> LocalSocket {
    guard let iface = HomeInterface.all.first(where: { $0.contains(host) }) else {
      throw RemoteError("Connect your iPhone to the same home network as your stereo.")
    }
    let socket = try LocalSocket(type: SOCK_STREAM, interface: iface)
    var address = ipv4(host, port)
    if withAddress(&address, { Darwin.connect(socket.fd, $0, $1) }) != 0 {
      var error: Int32 = 0
      var length: socklen_t = 4
      guard errno == EINPROGRESS, socket.ready(POLLOUT, until: end),
        getsockopt(socket.fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else {
        throw RemoteError("The device didn’t answer. Check its power and Wi-Fi.")
      }
    }
    return socket
  }

  func write(_ bytes: Data, until end: TimeInterval) throws {
    var written = 0
    while written < bytes.count && ready(POLLOUT, until: end) {
      let n = bytes.withUnsafeBytes { send(fd, $0.baseAddress!.advanced(by: written), $0.count - written, 0) }
      if n > 0 { written += n } else if n < 0 && (errno == EINTR || errno == EAGAIN) { continue } else { break }
    }
    guard written == bytes.count else { throw RemoteError("The device disconnected. Try again.") }
  }

  func read(until end: TimeInterval, complete: (Data) -> Bool) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while data.count < 32768 && ready(POLLIN, until: end) {
      let n = recv(fd, &buffer, buffer.count, 0)
      if n <= 0 { break }
      data.append(contentsOf: buffer.prefix(n))
      if complete(data) { break }
    }
    return data
  }
}

func localNetworkTask<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
  let task = Task.detached(operation: work)
  return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
}

enum LocalDiscovery {
  #if OTOHA_MULTICAST
  static let usesAnnouncements = true
  #else
  static let usesAnnouncements = false
  #endif

  // UPnP and BroadLink both support addressed discovery requests. Limit the fallback
  // to a home-sized broadcast domain and pace ARP resolution on Wi-Fi.
  static func addressed(port: UInt16, query: (HomeInterface, UInt16, String) -> [Data]) throws -> Set<Datagram> {
    var results = Set<Datagram>()
    var searched = false
    var delivered = false
    for iface in HomeInterface.all {
      let address = UInt32(bigEndian: iface.ip.s_addr)
      guard address >> 24 == 10 || address >> 20 == 0xac1 || address >> 16 == 0xc0a8 || address >> 16 == 0xa9fe else { continue }
      let mask = UInt32(bigEndian: iface.mask.s_addr)
      let network = address & mask, broadcast = network | ~mask
      guard broadcast - network > 1, broadcast - network <= 1023 else { continue }
      searched = true
      let socket = try LocalSocket(type: SOCK_DGRAM, interface: iface)
      try socket.bind(iface.host)
      let sourcePort = socket.port
      func receive(until end: TimeInterval) {
        while results.count < 256 && socket.ready(POLLIN, until: end) {
          guard let reply = socket.readDatagram() else { break }
          if iface.contains(reply.host) && reply.host != iface.host { results.insert(reply) }
        }
      }
      for peer in (network + 1)..<broadcast where peer != address {
        try Task.checkCancellation()
        let host = dotted(in_addr(s_addr: peer.bigEndian))
        for data in query(iface, sourcePort, host) {
          if (try? socket.datagram(data, to: host, port: port)) != nil { delivered = true }
        }
        if (peer - network).isMultiple(of: 8) { receive(until: LocalSocket.now + 0.045) }
      }
      let deadline = LocalSocket.now + 1.6
      while LocalSocket.now < deadline && results.count < 256 {
        try Task.checkCancellation()
        receive(until: min(deadline, LocalSocket.now + 0.12))
      }
    }
    guard searched else { throw RemoteError("Use your regular home Wi-Fi. This search needs a home-sized network.") }
    guard delivered else { throw RemoteError("Allow Otoha under Settings → Privacy & Security → Local Network, then search again.") }
    return results
  }

  // Listen for both replies to our query and unsolicited announcements (used by some BDS receivers).
  static func collect(group: String? = nil, port: UInt16, duration: TimeInterval = 2.4,
                      query: (HomeInterface, UInt16) -> [Data]) throws -> Set<Datagram> {
    let interfaces = HomeInterface.all
    guard !interfaces.isEmpty else { throw RemoteError("Connect your iPhone to your home Wi-Fi and search again.") }
    var readers: [LocalSocket] = []
    var queries: [(LocalSocket, String, Data)] = []
    var failure: Error?
    for iface in interfaces {
      do {
        let socket = try LocalSocket(type: SOCK_DGRAM, interface: iface)
        try socket.bind(iface.host)
        if group != nil {
          var source = iface.ip
          setsockopt(socket.fd, IPPROTO_IP, IP_MULTICAST_IF, &source, 4)
        } else {
          var yes: Int32 = 1
          setsockopt(socket.fd, SOL_SOCKET, SO_BROADCAST, &yes, 4)
        }
        for message in query(iface, socket.port) {
          let target = group ?? iface.broadcast
          try socket.datagram(message, to: target, port: port)
          queries.append((socket, target, message))
        }
        readers.append(socket)
      } catch { failure = error }
    }
    if readers.isEmpty { throw failure ?? RemoteError("Wi-Fi is unavailable.") }
    if let group, let listener = try? LocalSocket(type: SOCK_DGRAM) {
      var yes: Int32 = 1
      setsockopt(listener.fd, SOL_SOCKET, SO_REUSEADDR, &yes, 4)
      setsockopt(listener.fd, SOL_SOCKET, SO_REUSEPORT, &yes, 4)
      if (try? listener.bind("0.0.0.0", port: port)) != nil {
        for iface in interfaces {
          var membership = ip_mreq(imr_multiaddr: ipv4(group, port).sin_addr, imr_interface: iface.ip)
          setsockopt(listener.fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout.size(ofValue: membership)))
        }
        readers.append(listener)
      }
    }
    let start = LocalSocket.now
    var repeated = false
    var packets = Set<Datagram>()
    var pollers = readers.map { pollfd(fd: $0.fd, events: Int16(POLLIN), revents: 0) }
    while LocalSocket.now - start < duration && packets.count < 256 {
      try Task.checkCancellation()
      if !repeated && LocalSocket.now - start >= 0.7 {
        for (socket, host, message) in queries { try? socket.datagram(message, to: host, port: port) }
        repeated = true
      }
      if poll(&pollers, nfds_t(pollers.count), 100) > 0 {
        for i in readers.indices where pollers[i].revents & Int16(POLLIN) != 0 {
          if let packet = readers[i].readDatagram(), interfaces.contains(where: { $0.contains(packet.host) }) {
            packets.insert(packet)
          }
        }
      }
    }
    return packets
  }
}
