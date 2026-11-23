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
  @State private var selectedDeviceID: String?
  @State private var working = false
  @State private var draft: RemoteArrangement
  @State private var modeCycle: HarmanVolume.Cycle

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
    _modeCycle = State(initialValue: equipment?.harmanVolume.cycle ?? .standard)
  }

  var body: some View {
    NavigationStack {
      List {
        switch panel {
        case .connection: connections
        case .infraredOffer:
          if let state = remote.receiver, state.infrared != nil {
            let skip = {
              remote.finishInfraredOffer(for: state.device.id)
              dismiss()
            }
            Section {
              Text("Your " + state.model + " can disconnect from your home network in standby. When that happens, your iPhone can’t turn it on over Wi-Fi.")
              Text("An IR blaster, such as a BroadLink RM mini 3, sends the same infrared light signal as the On button on your handheld remote.")
            }
            Section {
              NavigationLink("Connect an IR blaster") {
                InfraredSettings(receiverId: state.device.id, skip: skip)
              }
              Button("Not now", action: skip)
            } footer: {
              Text("You can set this up later under Power → Infrared wake.")
            }
          }
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
            Picker("Mode after Off", selection: $modeCycle) {
              ForEach(HarmanVolume.Cycle.allCases, id: \.self) { cycle in
                Text(cycle.afterOff.rawValue).tag(cycle)
              }
            }
          } footer: {
            Text("If the modes advance in a different order on your receiver, choose the mode one press after Off.")
          }
          Section {
            ForEach(modeCycle.modes, id: \.self) { mode in
              Button(mode.rawValue) {
                if let id = equipment?.device.id, remote.syncHarmanVolume(mode, cycle: modeCycle, for: id) { dismiss() }
              }.disabled(remote.busy || remote.receiver?.online != true)
            }
          } header: {
            Text("Mode on the front display")
          } footer: {
            Text("Tap the mode you see to save it for this receiver. Otoha tracks its own presses. Sync again if the display changes with another remote.")
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
              Label("Infrared wake", systemImage: "dot.radiowaves.left.and.right")
            }
          }
        }
        if let note = remote.feedback, ![.connection, .infraredOffer, .frontPage].contains(panel) {
          Text(note).font(.footnote).foregroundStyle(.secondary)
        }
      }
      .safeAreaInset(edge: .bottom) {
        if panel == .connection { connectBar }
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
        } else if panel != .infraredOffer && (panel != .connection || equipment != nil) {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) }
        }
      }
      .task {
        guard panel == .connection else { return }
        if remote.receiver == nil { await locate() }
      }
      .tint(Palette.controlTint)
    }
    .onChange(of: remote.receiver?.irWake) { _, linked in
      if panel == .infraredOffer && linked == true {
        remote.notify("IR blaster connected for Power On.")
        dismiss()
      }
    }
    .interactiveDismissDisabled(working || panel == .infraredOffer || (panel == .connection && equipment == nil) || (panel == .frontPage && savedPage == nil))
  }
  private var title: String {
    switch panel {
    case .power: "Power"
    case .mode: "Sync Harman Volume"
    case .inputs: "More inputs"
    case .connection: equipment == nil ? "Select a device" : "Settings"
    case .infraredOffer: "Connect an IR blaster?"
    case .frontPage: savedPage == nil ? "Set up remote" : "Customize remote"
    }
  }
  @ViewBuilder private var connections: some View {
    if equipment != nil {
      Section {
        Button("Customize remote", systemImage: "slider.horizontal.3", action: editPage)
      }
    }
    if let device = remote.receiver?.device {
      Section {
        LabeledContent("Current device", value: device.name)
        LabeledContent("Connection", value: remote.activity)
      }
    }
    Section {
      ForEach(devices) { device in
        let selected = selectedDeviceID == device.id
        Button {
          selectedDeviceID = device.id
          receiverMessage = ""
        } label: {
          HStack {
            VStack(alignment: .leading) {
              Text(device.name).foregroundStyle(.primary)
              if device.model != device.name { Text(device.model).font(.footnote).foregroundStyle(.secondary) }
              if devices.filter({ $0.name == device.name && $0.model == device.model }).count > 1 {
                Text("Device ID ending in " + String(device.id.suffix(6))).font(.footnote)
              }
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
          }.contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(working || findingReceiver || remote.busy)
      }
      if findingReceiver { ProgressView("Finding devices…") }
      else {
        Button("Search for devices", systemImage: "arrow.clockwise") { Task { await locate() } }
          .disabled(working || remote.busy)
      }
    } header: {
      Text("Devices on your Wi-Fi")
    } footer: {
      Text("Turn on your Harman Kardon device and connect your iPhone to the same home network.")
    }
  }

  private var connectBar: some View {
    VStack(spacing: 8) {
      if !receiverMessage.isEmpty {
        Text(receiverMessage).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
      }
      Button {
        guard let selectedDeviceID, !working else { return }
        working = true
        Task {
          defer { working = false }
          do {
            try await remote.linkDevice(selectedDeviceID)
            dismiss()
          } catch { receiverMessage = error.localizedDescription }
        }
      } label: {
        Text(working ? "Connecting…" : "Connect").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(selectedDeviceID == nil || findingReceiver || working || remote.busy)
    }
    .padding().background(.bar)
  }

  private func locate() async {
    guard !findingReceiver, !working else { return }
    findingReceiver = true
    devices = []
    selectedDeviceID = nil
    receiverMessage = ""
    defer { findingReceiver = false }
    do {
      devices = try await remote.locateDevices()
      if devices.isEmpty {
        receiverMessage = "No devices found. Check that Otoha is allowed under Settings → Privacy & Security → Local Network, then search again."
      }
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
  var skip: (() -> Void)? = nil
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
        case "linked":
          Section {
            LabeledContent("Linked blaster", value: setup.label ?? "IR blaster")
            Text("Power on now sends your receiver’s infrared On signal.")
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
        case "readyToLearn":
          Section {
            LabeledContent("Blaster", value: setup.devices?.first?.label ?? "BroadLink RM")
            Text("Point the receiver’s remote at the blaster. If the remote has an AVR mode, select it first. Tap Learn Power On and wait for the listening prompt.")
            Button("Learn Power On") { submit("learn") }
            Button("Choose another blaster") { submit("search") }
          }
        case "preparing":
          ProgressView("Getting the blaster ready…")
        case "learning":
          Section {
            ProgressView("Listening for Power On…")
            Text("Press the receiver remote’s On button once now.")
          }
        default:
          let learning = remote.receiver?.device.infraredWake == .learnOn
          Section {
            Text("Connect the blaster to your home Wi-Fi using its manufacturer’s app. Place it where its infrared light can reach the front of your receiver.")
            if learning {
              Text("Use a BroadLink RM infrared blaster and have the receiver’s original remote handy to teach it Power On.")
            }
            DisclosureGroup("Compatible blasters and setup tips") {
              Text("For a BroadLink RM, turn off Lock device in the BroadLink app.")
              if !learning {
                Text("You can also use IRKit, a Nature Remo with local control, or a Tasmota IR transmitter with Bonjour, local HTTP access and an IRsend pin.")
              }
            }
          }
          Section {
            Button("Find a blaster") { submit("search") }
            if !learning && LocalDiscovery.usesAnnouncements {
              Button("Find a Global Caché iTach or Flex") { submit("itach") }
              Text("An iTach announces itself about once a minute.").font(.footnote)
            }
          } footer: {
            Text("Setup sends no power command.")
          }
        }
      } else {
        Text("Infrared setup is unavailable for this device.")
      }
      if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
    }
    .disabled(remote.busy)
    .safeAreaInset(edge: .bottom) {
      if let skip {
        Button("Not now", action: skip).frame(maxWidth: .infinity).padding().background(.bar)
      }
    }
    .onDisappear { searchTask?.cancel() }
    .navigationTitle("Infrared wake")
    .navigationBarTitleDisplayMode(.inline)
  }
}
