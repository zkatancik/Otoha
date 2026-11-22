import SwiftUI
import UIKit

struct VolumeFader: View {
  let enabled: Bool
  let height: CGFloat
  let step: @MainActor (Bool) async -> Bool
  @State private var position: CGFloat = 0
  @State private var pressedSide = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  private let amber = Color(red: 1, green: 0.52, blue: 0.28)

  var body: some View {
    HStack(spacing: 4) {
      VStack(alignment: .leading) {
        marking("Louder", symbol: "plus", active: pressedSide > 0 || position > 0.17)
        Spacer()
        marking("Quieter", symbol: "minus", active: pressedSide < 0 || position < -0.17)
      }
      .padding(.vertical, height < 110 ? 1 : 5)
      .padding(.leading, 15)
      GeometryReader { well in
        let travel = max(0, well.size.height - 54) / 2
        let center = CGPoint(x: well.size.width / 2, y: well.size.height / 2)
        ZStack {
          Canvas { context, _ in
            for mark in -4...4 {
              let length: CGFloat = mark.isMultiple(of: 2) ? 12 : 6
              let y = center.y + CGFloat(mark) * travel / 4
              let inset = min(64, well.size.width * 0.31)
              for side: CGFloat in [-1, 1] {
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + inset * side, y: y))
                tick.addLine(to: CGPoint(x: center.x + (inset + length) * side, y: y))
                context.stroke(
                  tick, with: .color(.white.opacity(mark == 0 ? 0.62 : 0.28)), lineWidth: 1.5)
              }
            }
          }
          Capsule().fill(.black)
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .frame(width: 11, height: max(0, well.size.height - 14))
          thumb
            .frame(width: min(119, max(0, well.size.width - 4)), height: 44)
            .offset(y: -position * travel)
            .anchorPreference(key: GripBounds.self, value: .bounds) { $0 }
        }
      }
      .padding(.trailing, 12)
    }
    .frame(height: height)
    .background(
      LinearGradient(
        colors: [Color(white: 0.075), Color(white: 0.13)],
        startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 17)
    )
    .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.12)))
    .opacity(enabled ? 1 : 0.54)
    .accessibilityHidden(true)
    .overlayPreferenceValue(GripBounds.self) { grip in
      GeometryReader { surface in
        FaderTouchSurface(
          enabled: enabled, gripFrame: grip.map { surface[$0] } ?? .zero,
          step: step, pressed: { pressedSide = $0 }
        ) { value, released in
          if released && !reduceMotion {
            withAnimation(.spring(duration: 0.23, bounce: 0.15)) { position = 0 }
          } else {
            position = value
          }
        }
      }
    }
  }

  private func marking(_ title: String, symbol: String, active: Bool) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol).font(.system(size: 14, weight: .bold)).frame(width: 15)
      if !typeSize.isAccessibilitySize {
        Text(title).font(.subheadline.weight(.semibold)).fixedSize()
      }
    }
    .padding(.horizontal, 8).frame(minHeight: 36)
    .foregroundStyle(active ? amber : .white.opacity(0.85))
    .background(.white.opacity(active ? 0.14 : 0.055), in: Capsule())
  }

  private var thumb: some View {
    let cap = RoundedRectangle(cornerRadius: 9)
    return ZStack {
      cap.fill(
        LinearGradient(
          stops: [
            .init(color: Color(white: 0.71), location: 0),
            .init(color: Color(white: 0.44), location: 0.18),
            .init(color: Color(white: 0.25), location: 0.47),
            .init(color: Color(white: 0.16), location: 0.53),
            .init(color: Color(white: 0.31), location: 0.86),
            .init(color: Color(white: 0.19), location: 1),
          ], startPoint: .top, endPoint: .bottom))
      cap.strokeBorder(.white.opacity(0.3))
      VStack(spacing: 3) {
        Capsule().fill(.black.opacity(0.35)).frame(width: 34, height: 2)
        Capsule().fill(amber).frame(height: 3).padding(.horizontal, 8)
        Capsule().fill(.black.opacity(0.45)).frame(width: 34, height: 2)
      }
    }.shadow(color: .black.opacity(0.7), radius: 3, y: 3)
  }
}

private enum GripBounds: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = nextValue() ?? value
  }
}

private struct FaderTouchSurface: UIViewRepresentable {
  let enabled: Bool
  let gripFrame: CGRect
  let step: @MainActor (Bool) async -> Bool
  let pressed: (Int) -> Void
  let moved: (CGFloat, Bool) -> Void

  func makeUIView(context: Context) -> FaderControl { FaderControl() }

  func updateUIView(_ view: FaderControl, context: Context) {
    view.gripFrame = gripFrame
    view.step = step
    view.pressed = pressed
    view.moved = moved
    if view.isEnabled != enabled { view.isEnabled = enabled }
  }

  static func dismantleUIView(_ view: FaderControl, coordinator: ()) {
    view.pressed = nil
    view.moved = nil
    view.isEnabled = false
  }
}

@MainActor
private final class FaderControl: UIControl, UIGestureRecognizerDelegate, RemoteDragControl {
  var gripFrame = CGRect.zero
  private var grabbed = false

  func reservesDrag(at point: CGPoint) -> Bool {
    isEnabled && !gripFrame.isEmpty && gripFrame.insetBy(dx: -12, dy: -8).contains(point)
  }
  var step: (@MainActor (Bool) async -> Bool)?
  var pressed: ((Int) -> Void)?
  var moved: ((CGFloat, Bool) -> Void)?
  private var origin: CGPoint?
  private var tapBegan: ContinuousClock.Instant?
  private var pendingTaps: [Bool] = []
  private var pull: CGFloat = 0
  private var direction = 0
  private var revision = 0
  private var first = true
  private var inFlight = false
  private var repeatTask: Task<Void, Never>?
  private let tick = UISelectionFeedbackGenerator()

  init() {
    super.init(frame: .zero)
    isExclusiveTouch = true
    isAccessibilityElement = true
    accessibilityTraits = .adjustable
    accessibilityLabel = "Master volume fader"
    accessibilityIdentifier = "volumeFader"
    accessibilityHint = "Swipe up or down to change the volume by one step."
    let grip = UILongPressGestureRecognizer(target: self, action: #selector(track(_:)))
    grip.minimumPressDuration = 0
    grip.allowableMovement = .greatestFiniteMagnitude
    grip.delegate = self
    addGestureRecognizer(grip)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  func gestureRecognizer(
    _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
  ) -> Bool {
    guard let scroll = other.view as? UIScrollView else { return false }
    return other === scroll.panGestureRecognizer && isDescendant(of: scroll)
  }

  override var isEnabled: Bool {
    didSet {
      for gesture in gestureRecognizers ?? [] { gesture.isEnabled = isEnabled }
      if !isEnabled {
        pendingTaps.removeAll()
        accessibilityTraits.insert(.notEnabled)
        releaseFader()
      } else {
        accessibilityTraits.remove(.notEnabled)
      }
    }
  }

  @objc private func track(_ gesture: UILongPressGestureRecognizer) {
    let finger = gesture.location(in: self)
    switch gesture.state {
    case .began:
      guard isEnabled else { return }
      origin = finger
      grabbed = reservesDrag(at: finger)
      tapBegan = .now
      let side = bounds.midY - finger.y
      pressed?(abs(side) <= 3 ? 0 : side > 0 ? 1 : -1)
      tick.prepare()
    case .changed:
      guard let origin, isEnabled else { return }
      // Allow vertical overshoot for a full throw. Sliding out sideways disengages the control.
      guard finger.x >= -8, finger.x <= bounds.width + 8 else {
        releaseFader()
        return
      }
      let distance = origin.y - finger.y
      if tapBegan != nil && (abs(distance) >= 9 || abs(finger.x - origin.x) >= 9) {
        tapBegan = nil
        pressed?(0)
      }
      guard grabbed else { return }
      let throwLength = max(1, (bounds.height - 54) / 2)
      pull = min(1, max(-1, distance / throwLength))
      moved?(pull, false)
      // A smaller release threshold keeps a resting thumb from chattering at the detent.
      let threshold: CGFloat = direction != 0 && distance * CGFloat(direction) > 0 ? 5 : 9
      steer(abs(distance) < threshold ? 0 : (distance > 0 ? 1 : -1))
    case .ended:
      let tap = tapBegan.map { $0.duration(to: .now) < .milliseconds(400) } == true
      let start = origin
      releaseFader()
      if tap, let start, bounds.contains(finger),
        abs(start.x - finger.x) < 9, abs(start.y - finger.y) < 9,
        abs(start.y - bounds.midY) > 3
      {
        singleStep(louder: start.y < bounds.midY)
      }
    case .cancelled, .failed: releaseFader()
    default: break
    }
  }

  func releaseFader() {
    guard origin != nil || direction != 0 else { return }
    origin = nil
    pressed?(0)
    tapBegan = nil
    pull = 0
    steer(0)
    moved?(0, true)
  }

  private func steer(_ newDirection: Int) {
    guard newDirection != direction else { return }
    direction = newDirection
    revision += 1
    first = true
    repeatTask?.cancel()
    repeatTask = nil
    if direction != 0 {
      pendingTaps.removeAll()
      sendStep()
    }
  }

  // Each acknowledgement rechecks the live gesture. Reversing during a slow request uses
  // the latest direction; releasing while it is in flight leaves nothing queued.
  private func sendStep() {
    guard !inFlight, isEnabled, direction != 0, let step else { return }
    let version = revision
    let louder = direction > 0
    inFlight = true
    Task { [weak self] in
      guard let self else { return }
      let start = ContinuousClock.now
      let accepted = self.revision == version ? await step(louder) : false
      self.inFlight = false
      guard self.isEnabled else { return }
      if self.direction == 0 {
        self.sendNextTap()
        return
      }
      guard self.revision == version else {
        self.sendStep()
        return
      }
      guard accepted else {
        self.releaseFader()
        return
      }
      self.tick.selectionChanged()
      let interval = self.first ? 0.48 : 0.62 - 0.42 * Double(abs(self.pull))
      self.first = false
      self.repeatTask = Task { [weak self] in
        do {
          try await Task.sleep(until: start.advanced(by: .seconds(interval)), clock: .continuous)
        } catch { return }
        guard let self, self.revision == version else { return }
        self.sendStep()
      }
    }
  }

  private func singleStep(louder: Bool) {
    guard isEnabled, window != nil, origin == nil else { return }
    pendingTaps.append(louder)
    sendNextTap()
  }

  private func sendNextTap() {
    guard isEnabled, !inFlight, !pendingTaps.isEmpty, direction == 0, let step else { return }
    let louder = pendingTaps.removeFirst()
    inFlight = true
    Task {
      if isEnabled, window != nil, await step(louder) {
        tick.selectionChanged()
      } else {
        pendingTaps.removeAll()
      }
      inFlight = false
      if direction == 0 { sendNextTap() } else { sendStep() }
    }
  }
  override func accessibilityIncrement() { singleStep(louder: true) }
  override func accessibilityDecrement() { singleStep(louder: false) }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      pendingTaps.removeAll()
      releaseFader()
    }
  }
}
