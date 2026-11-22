import SwiftUI

enum Palette {
  static let paper = adaptive(0xF1EEE8, 0x151815)
  static let ink = adaptive(0x242821, 0xF9F6ED)
  static let card = adaptive(0xFFFCF5, 0x2E322E)
  static let receiverTop = adaptive(0xE3E2D8, 0x333932)
  static let modeSurface = adaptive(0xDEDCCF, 0x35382F)
  static let controlTint = adaptive(0x694129, 0xFFC197)
  static let ember = adaptive(0xA94214, 0xFF9D69)
  static let status = adaptive(0x237643, 0x78CD8B)

  private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      uiColor: UIColor { traits in
        let rgb = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat(rgb >> 16) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
          blue: CGFloat(rgb & 255) / 255, alpha: 1)
      })
  }
}

enum Panel: String, Identifiable {
  case power, inputs, mode, connection, infraredOffer, frontPage
  var id: Self { self }
}

struct Source: Identifiable {
  let id, name, icon, detail: String
  static func available(_ receiver: Receiver?) -> [Source] {
    guard let sources = receiver?.sources else { return all }
    let mapped = sources.map { item in
      Source(
        id: item.id, name: item.name, icon: all.first { $0.id == item.id }?.icon ?? "hifispeaker",
        detail: item.detail)
    }
    if receiver?.device.profile == "stereo" {
      return ["phono", "tv"].compactMap { id in mapped.first { $0.id == id } }
        + mapped.filter { !["phono", "tv"].contains($0.id) }
    }
    return mapped
  }

  static let all = [
    Source(id: "phono", name: "Phono", icon: "opticaldisc", detail: "Turntable"),
    Source(id: "tv", name: "TV", icon: "tv", detail: "Television"),
    Source(
      id: "bluetooth", name: "Bluetooth", icon: "antenna.radiowaves.left.and.right",
      detail: "Wireless audio"),
    Source(id: "fm", name: "FM / AM", icon: "radio", detail: "Radio tuner"),
    Source(id: "cd", name: "CD", icon: "opticaldisc", detail: "Disc player"),
    Source(id: "network", name: "Network", icon: "network", detail: "Media server"),
    Source(id: "usb", name: "USB / iPod", icon: "cable.connector", detail: "Connected device"),
    Source(
      id: "cable", name: "Cable / Sat", icon: "antenna.radiowaves.left.and.right",
      detail: "Set-top box"),
    Source(id: "internet", name: "Internet radio", icon: "globe", detail: "vTuner"),
  ]
}

struct RemoteView: View {
  @EnvironmentObject private var remote: Remote
  @Environment(\.horizontalSizeClass) private var widthClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var scene
  @State private var panel: Panel?
  @State private var page = 0
  @State private var saved: RemoteArrangement?
  @State private var editingDeviceID: String?
  @State private var speakerLevel = 0.0

  private var equipment: Receiver? { remote.receiver }
  private var online: Bool { remote.receiver?.online == true }
  private var canControl: Bool { online && !remote.busy }
  private var deviceID: String? { equipment?.device.id }
  private var arrangement: RemoteArrangement {
    saved ?? equipment.map(RemoteArrangement.standard) ?? RemoteArrangement(modules: [], inputs: [])
  }

  var body: some View {
    NavigationStack {
      Group {
        if let equipment, deviceID != nil {
          dashboard(equipment)
        } else {
          ContentUnavailableView {
            VStack(spacing: 16) {
              OtohaSignature()
              Text("Select a device")
            }
          } description: {
            Text("Turn on your Harman Kardon stereo and join the same home Wi-Fi on your iPhone. Your stereo can also use a network cable to the router.")
          } actions: {
            Button("Select a device") { panel = .connection }.buttonStyle(.borderedProminent)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.paper.ignoresSafeArea())
      .navigationTitle("Remote")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu {
            if let equipment {
              ForEach(Source.available(equipment).filter { arrangement.inputs.contains($0.id) }) {
                source in
                Button(source.name, systemImage: source.icon) {
                  Task { await remote.send("source", source.id) }
                }
                .disabled(!canControl)
              }
              Button("Power", systemImage: "power") { panel = .power }
            }
            Button("Customize remote", systemImage: "slider.horizontal.3", action: editLayout)
              .disabled(deviceID == nil)
          } label: {
            Label("Quick actions", systemImage: "ellipsis")
          }
          .accessibilityIdentifier("quickActions")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") { panel = .connection }
            .accessibilityIdentifier("receiverSettings")
        }
      }
    }
    .foregroundStyle(Palette.ink).tint(Palette.controlTint)
    .overlay(alignment: .top) {
      if let text = remote.feedback, panel == nil {
        Text(text).font(.footnote.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
          .foregroundStyle(.white).background(.black.opacity(0.87), in: Capsule()).allowsHitTesting(
            false)
      }
    }
    .sheet(item: $panel, onDismiss: offerSetup) { item in
      ReceiverSheet(
        panel: item, savedPage: saved, arrangement: arrangement, equipment: equipment,
        editPage: editLayout
      ) { layout in
        guard let id = editingDeviceID, id == deviceID else { return }
        layout.save(id)
        saved = layout
        page = 0
        panel = nil
      }.environmentObject(remote)
        .presentationDetents(
          [.connection, .inputs, .infraredOffer, .frontPage].contains(item) ? [.large] : [.medium, .large]
        )
        .presentationDragIndicator(.visible)
    }
    .onChange(of: deviceID, initial: true) { _, id in
      saved = id.flatMap { key in equipment.flatMap { RemoteArrangement.load(key, receiver: $0) } }
      page = 0
      speakerLevel = 0
      if panel == .frontPage && editingDeviceID != id { panel = nil } else { offerSetup() }
    }
    .onChange(of: online) { _, connected in
      if connected && remote.hasPendingInfraredOffer { offerSetup() }
    }
    .sensoryFeedback(.impact(weight: .light), trigger: remote.pulse)
    .task(id: scene) {
      guard scene == .active else {
        if scene == .background { remote.disconnected() }
        return
      }
      while !Task.isCancelled {
        await remote.refresh()
        try? await Task.sleep(for: .seconds(5))
      }
    }
  }

  private func editLayout() {
    guard let id = deviceID else { return }
    editingDeviceID = id
    panel = .frontPage
  }
  private func offerSetup() {
    guard panel == nil else { return }
    if deviceID == nil { panel = .connection }
    else if remote.hasPendingInfraredOffer {
      if online { panel = .infraredOffer }
    }
    else if saved == nil { editLayout() }
  }

  private func dashboard(_ device: Receiver) -> some View {
    GeometryReader { geometry in
      let size = geometry.size
      let fold = division(in: geometry)
      let wide =
        fold != nil || widthClass == .regular || size.width >= 620 || size.width > size.height
      let order: [RemoteModule] = [.volume, .harman, .inputs, .power, .playback, .navigation]
      let supported = order.filter { RemoteModule.available(for: device).contains($0) }
      let selected = supported.filter { arrangement.modules.contains($0) }
      let primary =
        selected.isEmpty
        ? supported.filter { RemoteArrangement.standard(device).modules.contains($0) } : selected
      let extra = supported.filter { !primary.contains($0) }
      let layout = FaceGeometry(
        size: size, fold: fold, wide: wide, accessibility: typeSize.isAccessibilitySize,
        speaker: device.speaker, footer: 26)
      let faces = layout.pages(primary, extra: false) + layout.pages(extra, extra: true)
      if !faces.isEmpty {
        RemotePager(
          page: $page, count: faces.count, enabled: panel == nil && scene == .active,
          arrowInset: layout.splitX
        ) { index in
          face(faces[index], layout: layout, device: device)
        }
        .id(deviceID)
        .dynamicTypeSize(...(size.height < 550 ? DynamicTypeSize.accessibility1 : .accessibility2))
      }
    }.buttonStyle(RemoteKeyStyle())
  }

  @ViewBuilder private func face(_ face: RemoteFace, layout: FaceGeometry, device: Receiver)
    -> some View
  {
    if layout.tabletop, let fold = layout.fold {
      VStack(spacing: 0) {
        sidePanel(face, height: max(1, fold.minY), device: device, layout: layout)
        Color.clear.frame(height: fold.height)
        console(face, layout: layout, device: device)
      }
    } else if layout.wide {
      GeometryReader { area in
        HStack(spacing: 0) {
          sidePanel(face, height: area.size.height, device: device, layout: layout)
            .frame(width: layout.leftWidth)
          Color.clear.frame(width: layout.gutter)
          console(face, layout: layout, device: device)
        }
      }
    } else {
      VStack(spacing: 6) {
        if face.extra {
          HStack {
            Text("More controls").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(device.model).font(.caption.weight(.semibold)).foregroundStyle(Palette.controlTint)
          }.padding(.horizontal, 17).frame(height: layout.headerHeight(extra: true))
        } else {
          header(device, height: layout.headerHeight(extra: false)).padding(.horizontal, 12)
        }
        console(face, layout: layout, device: device)
      }
    }
  }

  private func header(_ device: Receiver, height: CGFloat) -> some View {
    EquipmentPlate(receiver: device, status: remote.activity, online: online, compact: height < 125)
      .frame(height: max(1, height))
  }

  private func sidePanel(
    _ face: RemoteFace, height: CGFloat, device: Receiver, layout: FaceGeometry
  ) -> some View {
    let sideMinimum = face.side.reduce(CGFloat.zero) { sum, item in
      sum
        + item.minimumHeight(
          compact: true, accessibility: layout.accessibility, speaker: device.speaker) + 7
    }
    let portraitHeight =
      face.side.isEmpty ? height : min(max(68, height - sideMinimum), height * 0.60)
    return VStack(spacing: 7) {
      header(device, height: portraitHeight)
      if !face.side.isEmpty { moduleColumn(face.side, device: device, compact: true) }
    }
    .padding(.horizontal, 12).frame(height: height)
  }

  private func console(_ face: RemoteFace, layout: FaceGeometry, device: Receiver) -> some View {
    HStack(spacing: 8) {
      ForEach(face.columns.indices, id: \.self) { column in
        moduleColumn(face.columns[column], device: device, compact: layout.compact)
      }
    }.padding(.horizontal, 12)
  }

  private func moduleColumn(_ modules: [RemoteModule], device: Receiver, compact: Bool) -> some View
  {
    GeometryReader { area in
      let minima = modules.map {
        $0.minimumHeight(
          compact: compact, accessibility: typeSize.isAccessibilitySize, speaker: device.speaker)
      }
      let budget = max(0, area.size.height - CGFloat(max(0, modules.count - 1)) * 7)
      let baseline = max(1, minima.reduce(0, +))
      let surplus = max(0, budget - baseline)
      let weight = max(1, modules.map(\.expansionWeight).reduce(0, +))
      VStack(spacing: 7) {
        ForEach(modules.indices, id: \.self) { index in
          let kind = modules[index]
          let height =
            minima[index] * min(1, budget / baseline) + surplus * kind.expansionWeight / weight
          module(kind, device: device, compact: compact).frame(height: height)
        }
      }
    }
  }

  @ViewBuilder private func module(
    _ kind: RemoteModule, device: Receiver, compact: Bool
  )
    -> some View
  {
    switch kind {
    case .volume:
      if device.speaker {
        VStack(alignment: .leading, spacing: 6) {
          Text("Speaker volume").font(.headline)
          Slider(value: $speakerLevel, in: 0...100, step: 1).accessibilityLabel(
            "Requested speaker volume")
          HStack {
            Button("Set \(Int(speakerLevel))%") {
              Task { await remote.send("speaker-volume", String(Int(speakerLevel))) }
            }
            Spacer()
            Button("Mute") { Task { await remote.send("mute-on") } }
            Button("Unmute") { Task { await remote.send("mute-off") } }
          }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(!canControl).padding(12)
          .background(
            Palette.card, in: RoundedRectangle(cornerRadius: 16))
      } else {
        volumeCard(compact: compact)
      }
    case .inputs: quickInputs
    case .power:
      HStack(spacing: 5) {
        Image(systemName: "power").foregroundStyle(Palette.ember).accessibilityHidden(true)
        Text("Power").font(.subheadline.bold())
        Spacer(minLength: 2)
        if remote.canWake {
          Button("On") { Task { await remote.send("wake") } }
            .disabled(remote.busy).accessibilityLabel("Power on")
        }
        Button("Standby") { Task { await remote.send("standby") } }.disabled(!canControl)
        Button {
          panel = .power
        } label: {
          Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Power options")
      }.frame(maxHeight: .infinity).font(.subheadline.weight(.semibold)).buttonStyle(
        PowerKeyStyle()
      )
      .padding(.leading, 12).padding(.trailing, 4)
      .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
      .accessibilityIdentifier("powerModule")
    case .harman: harmanCard
    case .playback: playback
    case .navigation: navigationPad
    }
  }

  private func division(in geometry: GeometryProxy) -> CGRect? {
    if #available(iOS 27.1, *), let region = geometry.reservedRegions(kind: .division).first {
      let f = region.frame
      let m = region.margins
      let division = CGRect(
        x: f.minX - m.leading, y: f.minY - m.top, width: f.width + m.leading + m.trailing,
        height: f.height + m.top + m.bottom
      )
      .intersection(CGRect(origin: .zero, size: geometry.size))
      return division.isNull ? nil : division
    }
    return nil
  }

  private func volumeCard(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 3 : 7) {
      HStack {
        Text("Master volume").font(.title3.weight(.semibold)).tracking(-0.6)
          .lineLimit(1).minimumScaleFactor(0.6)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 4)
        Button {
          Task { await remote.send("mute") }
        } label: {
          Label("Mute", systemImage: "speaker.slash.fill")
            .font(.subheadline.weight(.semibold)).padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(.white.opacity(0.1), in: Capsule())
        }.disabled(!canControl)
      }
      GeometryReader { travel in
        VolumeFader(
          enabled: canControl && scene == .active && panel == nil,
          height: max(0, travel.size.height)
        ) { louder in
          await remote.send(louder ? "louder" : "quieter")
        }
      }
      if !compact {
        Text("Tap + or − for one step. Drag to repeat.")
          .font(.footnote).foregroundStyle(.white.opacity(0.75))
          .padding(.leading, 3)
      }
    }
    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, compact ? 6 : 10)
    .foregroundStyle(.white)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.21, green: 0.23, blue: 0.20), Color(red: 0.095, green: 0.105, blue: 0.10),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 22))
  }

  private var harmanCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Harman Volume").font(.title3.weight(.semibold)).tracking(-0.6)
          .lineLimit(1).minimumScaleFactor(0.62)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 2)
        Button {
          panel = .mode
        } label: {
          Group {
            if typeSize.isAccessibilitySize {
              Text("Sync")
            } else {
              Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Palette.controlTint).frame(minWidth: 52, minHeight: 44).contentShape(
            Rectangle())
        }
        .accessibilityLabel("Sync Harman Volume with receiver display")
        .disabled(!canControl)
      }
      if let mode = remote.receiver?.trackedMode, online {
        HStack {
          ForEach(["High", "Low", "Off"], id: \.self) { option in
            Button {
              if option != mode { Task { await remote.send("set-mode", option) } }
            } label: {
              Text(option).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                .foregroundStyle(option == mode ? Palette.paper : Palette.controlTint)
                .background(
                  option == mode ? Palette.controlTint : Palette.card,
                  in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canControl)
            .accessibilityLabel("Harman Volume " + option)
            .accessibilityAddTraits(option == mode ? [.isSelected] : [])
          }
        }
      } else {
        HStack(spacing: 10) {
          cycle
          modeOrder.lineLimit(1).minimumScaleFactor(0.65)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12).padding(.top, 2)
      .padding(.bottom, 6)
      .background {
        ZStack(alignment: .trailing) {
          Palette.modeSurface
          Wave().stroke(Palette.controlTint.opacity(0.13), lineWidth: 1).frame(
            width: 126, height: 68)
        }.clipShape(RoundedRectangle(cornerRadius: 20))
      }
  }
  private var modeOrder: some View {
    Text("High · Low · Off").font(.caption.weight(.medium)).foregroundStyle(Palette.controlTint)
  }
  private var cycle: some View {
    Button {
      Task { await remote.send("harman") }
    } label: {
      Label("Cycle mode", systemImage: "arrow.clockwise").font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14).frame(minHeight: 44, maxHeight: .infinity).background(
          Palette.card, in: RoundedRectangle(cornerRadius: 10))
    }.disabled(!canControl)
  }
  private var quickInputs: some View {
    let available = Source.available(equipment)
    let pinned = available.filter { arrangement.inputs.contains($0.id) }
    return GeometryReader { geometry in
      let width = geometry.size.width
      let moreWidth = min(96, max(66, width * 0.25))
      HStack(spacing: 6) {
        if !pinned.isEmpty {
          let tileWidth = max(
            70, (width - moreWidth - 6) / CGFloat(min(2, pinned.count)) - (pinned.count > 1 ? 3 : 0)
          )
          ScrollView(.horizontal) {
            HStack(spacing: 6) {
              ForEach(pinned) { source in
                let selected = remote.receiver?.lastSource == source.id
                Button {
                  Task { await remote.send("source", source.id) }
                } label: {
                  inputTile(
                    source.name, icon: source.icon, color: Palette.ember, selected: selected)
                }.frame(width: tileWidth, height: geometry.size.height).disabled(!canControl)
                  .accessibilityLabel(source.name)
                  .accessibilityValue(selected ? "Last requested" : "")
              }
            }
          }.scrollIndicators(.hidden).scrollDisabled(pinned.count <= 2)
        }
        Button {
          panel = .inputs
        } label: {
          inputTile(
            pinned.isEmpty ? "Inputs" : "More inputs", icon: "ellipsis", color: Palette.controlTint,
            selected: false)
        }.frame(maxWidth: pinned.isEmpty ? .infinity : moreWidth)
          .accessibilityLabel("More inputs").accessibilityIdentifier("moreInputs")
      }
    }
  }

  private func inputTile(_ name: String, icon: String, color: Color, selected: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
        Spacer(minLength: 0)
        if selected {
          Circle().fill(Palette.ember).frame(width: 6, height: 6)
        }
      }
      Text(name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.68)
    }
    .padding(.horizontal, 11).frame(
      maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading
    )
    .background(Palette.card, in: shape)
    .overlay(
      shape.strokeBorder(
        selected ? Palette.ember : Palette.ink.opacity(0.16), lineWidth: selected ? 2 : 1)
    )
    .shadow(color: Palette.ink.opacity(0.12), radius: 0, y: 1.3)
  }

  private var playback: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Playback").font(.title3.weight(.semibold)).tracking(-0.6).accessibilityAddTraits(
        .isHeader)
      HStack(spacing: 5) {
        extraKey("previous", "backward.end.fill", "Previous")
        extraKey("play", "play.fill", "Play")
        extraKey("pause", "pause.fill", "Pause")
        extraKey("next", "forward.end.fill", "Next")
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12).background(
      Palette.receiverTop, in: RoundedRectangle(cornerRadius: 18))
  }

  private var navigationPad: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Receiver menu").font(.title3.bold()).accessibilityAddTraits(.isHeader)
      Grid(horizontalSpacing: 6, verticalSpacing: 5) {
        GridRow {
          extraKey("menu", "list.bullet", "Menu", text: true)
          extraKey("up", "chevron.up", "Up")
          extraKey("back", "arrow.uturn.backward", "Back", text: true)
        }
        GridRow {
          extraKey("left", "chevron.left", "Left")
          extraKey("ok", "circle.fill", "OK", text: true)
          extraKey("right", "chevron.right", "Right")
        }
        GridRow {
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          extraKey("down", "chevron.down", "Down")
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12).background(
      Palette.modeSurface, in: RoundedRectangle(cornerRadius: 18))
  }

  private func extraKey(_ action: String, _ icon: String, _ label: String, text: Bool = false)
    -> some View
  {
    Button {
      Task { await remote.send(action) }
    } label: {
      Group {
        if text {
          Text(label).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.65)
        } else {
          Image(systemName: icon).font(.headline)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
      .foregroundStyle(Palette.controlTint)
      .background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
    }.disabled(!canControl || equipment?.actions.contains(action) == false).accessibilityLabel(
      label
    ).accessibilityIdentifier("extra-" + action)
  }
}

private struct RemoteKeyStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
      .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.56)
  }
}

private struct Wave: Shape {
  func path(in rect: CGRect) -> Path {
    Path { p in
      for row in 0..<9 {
        for x in stride(from: 0.0, through: rect.width, by: 2) {
          let t = x / rect.width
          let y =
            rect.midY + Double(row - 4) * 2.4 + sin(t * 8 + Double(row) * 0.16) * 17
            * sin(t * Double.pi)
          if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
      }
    }
  }
}

private struct PowerKeyStyle: ButtonStyle {
  @Environment(\.isEnabled) var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.padding(.horizontal, 7).frame(
      minWidth: 44, minHeight: 44, maxHeight: .infinity
    )
    .foregroundStyle(Palette.controlTint)
    .opacity(enabled ? (configuration.isPressed ? 0.55 : 1) : 0.40)
    .contentShape(Rectangle())
  }
}
