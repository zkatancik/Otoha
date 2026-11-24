import SwiftUI

private enum HardwareArt {
  private static func key(_ label: String) -> String {
    label.lowercased().filter { !$0.isWhitespace }
  }

  private static let catalog: [String: String] = {
    guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "hardware"),
      let data = try? Data(contentsOf: url),
      let labels = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    var lookup = [String: String]()
    for (label, asset) in labels { lookup[key(label)] = asset }
    return lookup
  }()

  static func portrait(_ label: String) -> UIImage? {
    guard let asset = catalog[key(label)] else { return nil }
    return UIImage(named: "hardware/\(asset).webp")
  }
}

struct OtohaSignature: View {
  var body: some View {
    HStack(spacing: 7) {
      Image("OtohaMark").resizable().interpolation(.high).frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text("Otoha").font(.system(size: 21, weight: .heavy, design: .rounded)).tracking(-1.05)
    }.accessibilityElement(children: .ignore).accessibilityLabel("Otoha")
  }
}

struct ConnectionLabel: View {
  let connection: Receiver.Connection
  var showsStatusLight = false

  var body: some View {
    HStack(spacing: 5) {
      if connection == .connecting {
        ProgressView().controlSize(.mini).accessibilityHidden(true)
      } else if showsStatusLight {
        Circle().fill(connection == .connected ? Color(red: 0.06, green: 0.29, blue: 0.14) : .black.opacity(0.5))
          .frame(width: 6, height: 6).accessibilityHidden(true)
      }
      Text(connection.rawValue)
    }
  }
}

struct EquipmentPlate: View {
  let receiver: Receiver
  let compact: Bool

  var body: some View {
    Group {
      if compact {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 1) {
            OtohaSignature()
            modelName
            emitterName
          }.layoutPriority(1)
          Spacer(minLength: 0)
          VStack(alignment: .trailing, spacing: 1) {
            statusLight
            portraits
          }
        }
      } else {
        VStack(spacing: 5) {
          HStack {
            OtohaSignature()
            Spacer(minLength: 5)
            statusLight
          }
          HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
              Text("harman/kardon").font(.system(size: 11, weight: .semibold)).tracking(-0.4)
              modelName
              emitterName
            }
            Spacer(minLength: 0)
            portraits
          }
        }
      }
    }
    .padding(.horizontal, compact ? 12 : 15).padding(.vertical, compact ? 7 : 11)
    .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.095))
    .background {
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 1, green: 0.75, blue: 0.54), Color(red: 1, green: 0.56, blue: 0.32),
            Color(red: 0.91, green: 0.45, blue: 0.25),
          ],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        Canvas { context, size in
          for x in stride(from: size.width * 0.44, to: size.width, by: 8) {
            for y in stride(from: 0, to: size.height, by: 8) {
              context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: 0.9, height: 0.9)),
                with: .color(.black.opacity(0.15 * x / max(1, size.width))))
            }
          }
        }
      }.clipShape(RoundedRectangle(cornerRadius: 18))
    }
    .accessibilityIdentifier("linkedEquipment")
  }

  private var modelName: some View {
    Text(receiver.model).font(.system(size: compact ? 20 : 34, weight: .black))
      .lineLimit(1).minimumScaleFactor(0.68).tracking(compact ? -0.8 : -1.5)
  }

  @ViewBuilder private var emitterName: some View {
    if let label = receiver.emitterLabel {
      let name = label
        .replacingOccurrences(of: "Global Caché ", with: "", options: [.anchored, .caseInsensitive])
        .replacingOccurrences(of: "BroadLink ", with: "", options: [.anchored, .caseInsensitive])
      Text("+ " + name).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
    }
  }

  private var statusLight: some View {
    ConnectionLabel(connection: receiver.connection, showsStatusLight: true)
      .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.72)
      .tint(.black.opacity(0.75))
  }

  private var portraits: some View {
    HStack(alignment: .bottom, spacing: -4) {
      if let portrait = HardwareArt.portrait(receiver.model) {
        Image(uiImage: portrait).resizable().scaledToFit()
      } else {
        Image(systemName: receiver.speaker ? "hifispeaker.2.fill" : "hifispeaker.fill")
          .resizable().scaledToFit().padding(9)
      }
      if let label = receiver.emitterLabel, let portrait = HardwareArt.portrait(label) {
        Image(uiImage: portrait).resizable().scaledToFit().frame(width: compact ? 26 : 38)
          .padding(.bottom, compact ? 3 : 6)
      }
    }
    .frame(maxWidth: compact ? 180 : 265, maxHeight: .infinity)
    .shadow(color: .black.opacity(0.24), radius: 3, y: 4).accessibilityHidden(true)
  }
}
