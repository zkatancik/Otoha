import SwiftUI

struct ReceiverSheet: View {
  let panel: Panel
  let savedPage: RemoteArrangement?
  let equipment: Receiver?
  let arrangement: RemoteArrangement
  let editPage: () -> Void
  let savePage: (RemoteArrangement) -> Void
  @EnvironmentObject private var remote: Remote
  @Environment(\.dismiss) private var dismiss
  @State private var findingReceiver = false
  @State private var receiverMessage = ""
  @State private var devices: [HKDevice] = []
  @State private var working = false
  @State private var draft: RemoteArrangement

  init(
    panel: Panel, savedPage: RemoteArrangement?, arrangement: RemoteArrangement,
    equipment: Receiver?,
    editPage: @escaping () -> Void, savePage: @escaping (RemoteArrangement) -> Void
  ) {
    self.panel = panel
    self.savedPage = savedPage
    self.equipment = equipment
    self.arrangement = arrangement
    self.editPage = editPage
    self.savePage = savePage
    _draft = State(initialValue: arrangement)
  }

  var body: some View {
    NavigationStack {
      List {
        switch panel {
        case .connection: connections
        case .frontPage:
          if let equipment {
            Section {
              EquipmentPlate(
                receiver: equipment, status: remote.activity,
                online: remote.receiver?.online == true, compact: true
              )
              .frame(height: 90).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
              ForEach(RemoteModule.available(for: equipment)) { module in
                let included = draft.modules.contains(module)
                Button {
                  if included { draft.modules.remove(module) } else { draft.modules.insert(module) }
                } label: {
                  HStack {
                    Label(module.name, systemImage: module.symbol).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                  }.contentShape(Rectangle())
                }
                .accessibilityLabel(module.name)
                .accessibilityAddTraits(included ? .isSelected : [])
                .accessibilityIdentifier("module-" + module.rawValue)
              }
            } header: {
              Text("On your remote")
            } footer: {
              Text(
                "Choose the modules you want at hand. Pull down on the remote to reach the others.")
            }
            if draft.modules.contains(.inputs) {
              Section {
                ForEach(Source.available(equipment)) { source in
                  Button {
                    if !draft.inputs.insert(source.id).inserted { draft.inputs.remove(source.id) }
                  } label: {
                    HStack {
                      Label(source.name, systemImage: source.icon).foregroundStyle(.primary)
                      Spacer()
                      Image(
                        systemName: draft.inputs.contains(source.id)
                          ? "checkmark.circle.fill" : "circle")
                    }.contentShape(Rectangle())
                  }.accessibilityLabel(source.name)
                    .accessibilityIdentifier("pin-" + source.id)
                    .accessibilityAddTraits(draft.inputs.contains(source.id) ? .isSelected : [])
                }
              } header: {
                Text("Quick inputs")
              } footer: {
                Text("Other sources stay under More inputs.")
              }
            }
            Button("Restore recommended modules") { draft = .standard(equipment) }
          }
        case .inputs:
          let sources = Source.available(equipment)
          let other = sources.filter { !arrangement.inputs.contains($0.id) }
          ForEach(other.isEmpty ? sources : other) { source in
            actionRow(source.name, source.detail, source.icon, "source", source.id)
          }
        case .mode:
          Section {
            ForEach(["High", "Low", "Off"], id: \.self) { mode in
              actionRow(mode, nil, "waveform", "sync-mode", mode)
            }
          } header: {
            Text("Mode on the front display")
          } footer: {
            Text(
              "Otoha counts the mode presses it sends from this setting. Sync again after changing the mode with another remote."
            )
          }
        case .power:
          Section {
            if remote.canWake {
              actionRow(
                "Power on",
                remote.receiver?.irWake == true ? "Infrared blaster" : "Try network wake",
                "power", "wake")
            }
            actionRow("Standby", nil, "moon", "standby")
            if remote.receiver?.speaker != true {
              actionRow("Sleep timer", "Advance the receiver timer", "timer", "sleep")
            }
          }
          if let setup = remote.receiver?.infrared {
            NavigationLink {
              InfraredSettings(receiverId: setup.receiverId)
            } label: {
              Label(
                remote.receiver?.irWake == true ? "Infrared wake" : "Power on troubleshooting",
                systemImage: remote.receiver?.irWake == true ? "dot.radiowaves.left.and.right" : "questionmark.circle")
            }
          }
        }
        if let note = remote.feedback, ![.connection, .frontPage].contains(panel) {
          Text(note).font(.footnote).foregroundStyle(.secondary)
        }
      }
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if panel == .frontPage {
          ToolbarItem(placement: .cancellationAction) {
            Button(savedPage == nil ? "Use defaults" : "Cancel") {
              if savedPage == nil, let equipment {
                savePage(.standard(equipment))
              } else {
                dismiss()
              }
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(savedPage == nil ? "Open remote" : "Save") { savePage(draft) }.disabled(
              draft.modules.isEmpty)
          }
        } else {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
      }
      .task {
        guard panel == .connection else { return }
        if remote.receiver == nil { await locate() }
      }
      .tint(Palette.controlTint)
    }
  }
  private var title: String {
    switch panel {
    case .power: "Power"
    case .mode: "Sync Harman Volume"
    case .inputs: "More inputs"
    case .connection: equipment == nil ? "Find your stereo" : "Settings"
    case .frontPage: savedPage == nil ? "Set up remote" : "Customize remote"
    }
  }
  @ViewBuilder private var connections: some View {
    if equipment != nil {
      Section {
        Button("Customize remote", systemImage: "slider.horizontal.3", action: editPage)
      }
    }
    Section("Your stereo") {
      if let device = remote.receiver?.device {
        LabeledContent("Linked device", value: device.name)
      }
      LabeledContent("Connection", value: remote.activity)
      Button(findingReceiver ? "Locating…" : "Locate devices") { Task { await locate() } }
        .disabled(findingReceiver || working || remote.busy)
      ForEach(devices) { device in
        Button {
          Task {
            working = true
            receiverMessage = "Connecting to " + device.name + "…"
            defer { working = false }
            do {
              try await remote.linkDevice(device.id)
              devices = []
              remote.notify("Linked to " + device.name + ".")
              dismiss()
            } catch { receiverMessage = error.localizedDescription }
          }
        } label: {
          VStack(alignment: .leading) {
            Text("Link " + device.name)
            if device.model != device.name { Text(device.model).font(.footnote).foregroundStyle(.secondary) }
            if devices.filter({ $0.name == device.name && $0.model == device.model }).count > 1 {
              Text("Device ID ending in " + String(device.id.suffix(6))).font(.footnote)
            }
          }
        }.disabled(working || findingReceiver || remote.busy)
      }
    }
    if !receiverMessage.isEmpty { Text(receiverMessage).font(.footnote) }
  }

  private func locate() async {
    findingReceiver = true
    devices = []
    receiverMessage = ""
    defer { findingReceiver = false }
    do {
      devices = try await remote.locateDevices()
      receiverMessage =
        devices.isEmpty
        ? "No stereo found. Turn it on, join your regular home Wi-Fi, and allow Otoha under Settings → Privacy & Security → Local Network. Then tap Locate devices again."
        : "Choose the device to link."
    } catch { receiverMessage = error.localizedDescription }
  }

  private func actionRow(
    _ title: String, _ detail: String?, _ icon: String, _ name: String, _ value: String? = nil
  ) -> some View {
    Button {
      Task {
        if await remote.send(name, value) { dismiss() }
      }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: icon).frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).foregroundStyle(.primary)
          if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        }
        Spacer()
      }.frame(minHeight: 44)
    }.disabled(
      remote.busy || (name == "wake" ? !remote.canWake : remote.receiver?.online != true))
  }
}

private struct InfraredSettings: View {
  let receiverId: String
  @EnvironmentObject private var remote: Remote
  @State private var error = ""
  @State private var confirmForget = false
  @State private var confirmedHandsetWake = false
  @State private var searchTask: Task<Void, Never>?

  private func submit(_ action: String, id: String? = nil) {
    error = ""
    searchTask = Task {
      do { try await remote.configureInfrared(action, receiverId: receiverId, id: id) } catch {
        self.error = error.localizedDescription
      }
    }
  }

  var body: some View {
    List {
      if let setup = remote.receiver?.infrared, setup.receiverId == receiverId {
        switch setup.phase {
        case "linked", "broken":
          Section {
            if let message = setup.message {
              Text(message)
            } else {
              LabeledContent("Linked blaster", value: setup.label ?? "IR blaster")
              Text("Power on now sends the HK 3770’s infrared On signal.")
            }
            Button("Forget blaster", role: .destructive) { confirmForget = true }
              .confirmationDialog("Forget this blaster?", isPresented: $confirmForget) {
                Button("Forget blaster", role: .destructive) { submit("forget") }
              } message: {
                Text("Power on will use network wake again.")
              }
          }
        case "searching", "linking":
          Section {
            ProgressView(setup.phase == "searching" ? "Finding blasters…" : "Linking blaster…")
            Text(
              "Keep Otoha open while your iPhone looks on your home Wi-Fi."
            )
          }
        case "choose":
          Section("Choose the blaster near your receiver") {
            ForEach(setup.devices ?? []) { device in
              Button {
                submit("select", id: device.id)
              } label: {
                VStack(alignment: .leading) {
                  Text(device.label)
                  Text("ID ending in \(device.id.suffix(6))").font(.footnote)
                }
              }
            }
            Button("Search again") { submit("search") }
          }
        case "idle" where !confirmedHandsetWake:
          Section {
            Text("First check that volume works from Otoha while your HK 3770 is on. Put the receiver in standby, then try Power on from Otoha while your iPhone is on the same Wi-Fi.")
            Text("If the receiver stays in standby, try the On button on its original handset.")
            Button("Wi-Fi wake failed, but the handset worked") { confirmedHandsetWake = true }
          }
        default:
          Section {
            Text("An infrared blaster can wake your HK 3770 the same way its original remote does. Plug the blaster in, connect it to your home network, and point it at the front of the stereo.")
            DisclosureGroup("Compatible blasters and setup tips") {
              Text("Choose a BroadLink RM, IRKit, a Nature Remo that supports local control, or a Tasmota IR transmitter.")
              Text("For BroadLink, turn off Lock device in its app. Tasmota needs Bonjour advertising, local HTTP access and an IRsend pin.")
            }
          }
          Section {
            if let message = setup.message { Text(message).foregroundStyle(.secondary) }
            Button("Find and link a blaster") { submit("search") }
            if LocalDiscovery.usesAnnouncements {
              Button("Find a Global Caché iTach or Flex") { submit("itach") }
              Text("An iTach announces itself about once a minute.").font(.footnote)
            }
          } footer: {
            Text(
              "Your iPhone links a single match automatically. Setup sends no power command."
            )
          }
        }
      } else {
        Text("Reconnect to your HK 3770 to manage infrared wake.")
      }
      if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
    }
    .disabled(remote.busy)
    .onDisappear { searchTask?.cancel() }
    .navigationTitle(confirmedHandsetWake || remote.receiver?.irWake == true ? "Infrared wake" : "Power on troubleshooting")
    .navigationBarTitleDisplayMode(.inline)
  }
}
