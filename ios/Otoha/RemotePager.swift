import SwiftUI
import UIKit

/// The physical thumb has an independent vertical gesture. The surrounding faceplate
/// belongs to the pager, including the space around the thumb.
@MainActor protocol RemoteDragControl: AnyObject {
  func reservesDrag(at point: CGPoint) -> Bool
}

struct RemotePager<Content: View>: View {
  @Binding var page: Int
  let count: Int
  let enabled: Bool
  let arrowInset: CGFloat
  @ViewBuilder let content: (Int) -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var offset: CGFloat = 0
  @State private var settling = false
  @State private var revision = 0
  @State private var armed = false

  static var arrowHeight: CGFloat { 26 }
  private let seam: CGFloat = 34

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let index = max(0, min(page, count - 1))
      let stride = size.height + seam
      ZStack(alignment: .top) {
        let moving = settling || offset != 0
        let visible = moving ? max(0, index - 1)..<min(count, index + 2) : index..<(index + 1)
        ForEach(visible, id: \.self) { item in
          let position = CGFloat(item - index) * stride - offset
          VStack(spacing: 0) {
            content(item)
            if count > 1 {
              HStack(spacing: 0) {
                if arrowInset > 0 { Color.clear.frame(width: arrowInset) }
                HStack(spacing: 18) {
                  if item > 0 { arrow(forward: false, index: index, height: size.height) }
                  if item < count - 1 { arrow(forward: true, index: index, height: size.height) }
                }.frame(maxWidth: .infinity)
              }.frame(height: Self.arrowHeight)
            }
          }
          .frame(width: size.width, height: size.height)
          .background(Palette.paper)
          .allowsHitTesting(item == index && offset == 0 && !settling)
          .accessibilityElement(children: .contain)
          .accessibilityHidden(item != index)
          .offset(y: position)
          .transition(.identity)
        }
        if offset != 0 {
          let forward = offset > 0
          Text(forward ? "Pull for more options" : "Pull to go back")
            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.controlTint)
            .frame(width: size.width, height: seam)
            .background(Palette.modeSurface)
            .offset(y: forward ? size.height - offset : -offset - seam)
            .accessibilityHidden(true).allowsHitTesting(false)
        }
      }
      .frame(width: size.width, height: size.height, alignment: .top)
      .clipped()
      .background {
        PagePan(
          available: enabled && count > 1 && !settling, previous: index > 0,
          next: index + 1 < count
        ) { distance, ended, cancelled in
          let hasTarget = distance > 0 ? index + 1 < count : index > 0
          let length = hasTarget ? abs(distance) : 0
          // The first part of the stroke opens only the narrow, labelled seam.
          let opening: CGFloat = 25
          let detent: CGFloat = 54
          let threshold = min(124, max(84, size.height * 0.17))
          let preview = min(length, opening) * seam / opening
          let reveal = max(0, length - detent) * min(2.7, max(1.55, size.height / 275))
          let sign: CGFloat = distance >= 0 ? 1 : -1
          if ended {
            let target = !cancelled && length >= threshold ? index + Int(sign) : index
            settle(from: index, to: target, height: size.height)
          } else {
            offset = sign * min(stride, preview + reveal)
            armed = length >= threshold
          }
        }
      }
      .onChange(of: size) { reset() }
      .onChange(of: count) {
        reset()
        page = max(0, min(page, count - 1))
      }
      .onChange(of: enabled) { if !enabled { reset() } }
      .onDisappear { reset() }
    }
    .sensoryFeedback(.impact(weight: .light), trigger: armed) { !$0 && $1 }
  }

  private func arrow(forward: Bool, index: Int, height: CGFloat) -> some View {
    Button {
      settle(from: index, to: index + (forward ? 1 : -1), height: height)
    } label: {
      Image(systemName: forward ? "chevron.down" : "chevron.up")
        .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.controlTint)
        .frame(width: 68, height: Self.arrowHeight).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(forward ? "Show more controls" : "Previous controls")
    .accessibilityIdentifier(forward ? "nextRemotePage" : "previousRemotePage")
  }

  private func settle(from index: Int, to next: Int, height: CGFloat) {
    guard !settling, (0..<count).contains(next) else { return }
    let token = revision
    settling = true
    armed = false
    withAnimation(
      reduceMotion ? nil : .smooth(duration: next == index ? 0.23 : 0.32),
      completionCriteria: .removed
    ) {
      offset = CGFloat(next - index) * (height + seam)
    } completion: {
      guard token == revision else { return }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        page = next
        offset = 0
        settling = false
      }
    }
  }

  private func reset() {
    revision += 1
    offset = 0
    settling = false
    armed = false
  }
}

/// Observe the initial touch on the whole viewport without covering native buttons,
/// source scrollers, or the volume control with a hit-testing overlay.
private struct PagePan: UIViewRepresentable {
  let available: Bool
  let previous: Bool
  let next: Bool
  let update: (CGFloat, Bool, Bool) -> Void

  func makeUIView(context: Context) -> Surface { Surface() }
  func updateUIView(_ view: Surface, context: Context) {
    view.configuration = self
  }
  static func dismantleUIView(_ view: Surface, coordinator: ()) { view.detach() }

  final class Surface: UIView, UIGestureRecognizerDelegate {
    var configuration: PagePan?
    private lazy var pan: UIPanGestureRecognizer = {
      let gesture = UIPanGestureRecognizer(target: self, action: #selector(track(_:)))
      gesture.maximumNumberOfTouches = 1
      gesture.delegate = self
      return gesture
    }()

    override func didMoveToWindow() {
      super.didMoveToWindow()
      detach()
      window?.addGestureRecognizer(pan)
    }
    func detach() { pan.view?.removeGestureRecognizer(pan) }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard configuration?.available == true, bounds.contains(touch.location(in: self)) else {
        return false
      }
      var view = touch.view
      while let candidate = view {
        if let control = candidate as? RemoteDragControl,
          control.reservesDrag(at: touch.location(in: candidate))
        {
          return false
        }
        view = candidate.superview
      }
      return true
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
      guard gesture === pan, let configuration, configuration.available else { return false }
      let v = pan.velocity(in: window)
      guard abs(v.y) > abs(v.x) * 1.2 else { return false }
      return v.y > 0 ? configuration.next : configuration.previous
    }

    func gestureRecognizer(
      _ gesture: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    @objc private func track(_ gesture: UIPanGestureRecognizer) {
      let distance = gesture.translation(in: window).y
      switch gesture.state {
      case .began, .changed: configuration?.update(distance, false, false)
      case .ended: configuration?.update(distance, true, false)
      case .cancelled, .failed: configuration?.update(0, true, true)
      default: break
      }
    }
  }
}
