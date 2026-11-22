import Foundation

enum RemoteModule: String, CaseIterable, Identifiable, Codable {
  case volume, power, inputs, harman, playback, navigation
  var id: Self { self }
  var name: String {
    switch self {
    case .volume: "Volume"
    case .power: "Power"
    case .inputs: "Inputs"
    case .harman: "Harman Volume"
    case .playback: "Playback"
    case .navigation: "Receiver menu"
    }
  }
  var symbol: String {
    switch self {
    case .volume: "slider.vertical.3"
    case .power: "power"
    case .inputs: "cable.connector"
    case .harman: "waveform"
    case .playback: "playpause.fill"
    case .navigation: "arrow.up.and.down.and.arrow.left.and.right"
    }
  }
  var commands: [String] {
    switch self {
    case .volume: ["quieter", "louder", "mute", "mute-on", "mute-off", "speaker-volume"]
    case .power: ["wake", "standby", "sleep"]
    case .inputs: []
    case .harman: ["harman"]
    case .playback: ["previous", "play", "pause", "next"]
    case .navigation: ["menu", "up", "left", "ok", "right", "down", "back"]
    }
  }
  static func available(for receiver: Receiver) -> [Self] {
    allCases.filter { module in
      if module == .inputs { return !Source.available(receiver).isEmpty && !receiver.speaker }
      if module == .volume && receiver.speaker { return true }
      return !Set(module.commands).isDisjoint(with: receiver.actions)
    }
  }
}

struct RemoteArrangement: Codable, Equatable {
  var modules: Set<RemoteModule>
  var inputs: Set<String>
  static let storageKey = "remoteModulesByDevice.v1"

  static func standard(_ receiver: Receiver) -> Self {
    let available = RemoteModule.available(for: receiver)
    var modules = Set(available.filter { [.volume, .power, .inputs, .harman].contains($0) })
    if modules.isEmpty, let first = available.first { modules.insert(first) }
    return Self(modules: modules, inputs: Set(Source.available(receiver).prefix(2).map(\.id)))
  }
  static func load(_ id: String, receiver: Receiver, defaults: UserDefaults = .standard) -> Self? {
    if let data = (defaults.dictionary(forKey: storageKey) ?? [:])[id] as? Data,
      let saved = try? JSONDecoder().decode(Self.self, from: data)
    {
      return saved
    }
    guard let old = (defaults.dictionary(forKey: "frontPagesByDevice.v1")?[id]) as? [String] else {
      return nil
    }
    let standard = standard(receiver)
    let inputs = Set(old.filter { $0.hasPrefix("source.") }.map { String($0.dropFirst(7)) })
    var modules = Set(
      RemoteModule.available(for: receiver).filter { !Set($0.commands).isDisjoint(with: old) })
    if !inputs.isEmpty { modules.insert(.inputs) }
    return modules.isEmpty ? standard : Self(modules: modules, inputs: inputs)
  }
  func save(_ id: String, defaults: UserDefaults = .standard) {
    var values = defaults.dictionary(forKey: Self.storageKey) ?? [:]
    values[id] = try? JSONEncoder().encode(self)
    defaults.set(values, forKey: Self.storageKey)
  }
}

// A compact layout keeps a module together. Overflow pages contain whole modules.
enum ModulePages {
  static func make(
    _ modules: [RemoteModule], height: CGFloat, compact: Bool,
    accessibility: Bool, speaker: Bool
  ) -> [[RemoteModule]] {
    var pages: [[RemoteModule]] = []
    var used: CGFloat = 0
    for module in modules {
      let minimum = module.minimumHeight(
        compact: compact, accessibility: accessibility, speaker: speaker)
      if pages.isEmpty || (used > 0 && used + minimum + 7 > height) {
        pages.append([])
        used = 0
      }
      used += (used == 0 ? 0 : 7) + minimum
      pages[pages.count - 1].append(module)
    }
    return pages.isEmpty ? [[]] : pages
  }
}

extension RemoteModule {
  func minimumHeight(compact: Bool, accessibility: Bool, speaker: Bool) -> CGFloat {
    switch self {
    case .volume: speaker ? 154 : compact ? 150 : 216
    case .power: accessibility ? 58 : 44
    case .inputs: 56
    case .harman: accessibility ? 125 : 103
    case .playback: accessibility ? 121 : 102
    case .navigation: accessibility ? 236 : 219
    }
  }

  var expansionWeight: CGFloat {
    switch self {
    case .volume: 5
    case .navigation: 3
    case .harman, .playback: 2
    case .inputs: 1.4
    case .power: 1
    }
  }
}

struct RemoteFace {
  let side: [RemoteModule]
  let columns: [[RemoteModule]]
  let extra: Bool
}

/// All dimensions are in the remote's safe viewport, including the Duo division.
struct FaceGeometry {
  let size: CGSize
  let fold: CGRect?
  let wide, accessibility, speaker: Bool
  let footer: CGFloat
  var tabletop: Bool { fold.map { $0.width > $0.height } ?? false }
  var compact: Bool { accessibility || (wide ? tabletop || size.height < 455 : size.height < 620) }
  var leftWidth: CGFloat { max(1, fold?.minX ?? (size.width - 8) / 2) }
  var gutter: CGFloat { fold?.width ?? 8 }
  var splitX: CGFloat { wide && !tabletop ? leftWidth + gutter : 0 }

  func headerHeight(extra: Bool) -> CGFloat {
    if extra { return compact ? 42 : 52 }
    if compact { return size.height < 565 ? 82 : 94 }
    return min(174, size.height * 0.22)
  }
  func pages(_ modules: [RemoteModule], extra: Bool) -> [RemoteFace] {
    guard !modules.isEmpty else { return [] }
    let main = modules.filter { $0 != .inputs && $0 != .power }
    let side = wide && !main.isEmpty ? modules.filter { !main.contains($0) } : []
    let bank = wide && !main.isEmpty ? main : modules
    var height = size.height - footer
    if tabletop {
      height -= fold?.maxY ?? 0
    } else if !wide {
      height -= headerHeight(extra: extra) + 6
    }
    let columns = ModulePages.make(
      bank, height: max(1, height), compact: compact,
      accessibility: accessibility, speaker: speaker)
    let span = tabletop ? 2 : 1
    return stride(from: 0, to: columns.count, by: span).map { start in
      RemoteFace(
        side: side, columns: Array(columns[start..<min(start + span, columns.count)]), extra: extra)
    }
  }
}
