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
  let layout: FaceGeometry
  @ViewBuilder let content: (Int) -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var offset: CGFloat = 0
  @State private var settling = false
  @State private var revision = 0

  var body: some View {
    let size = layout.size
    let index = max(0, min(page, count - 1))
    let height = max(0, size.height - (count > 1 ? layout.footer : 0))
    let moving = offset != 0 || settling
    let visible = moving ? max(0, index - 1)..<min(count, index + 2) : index..<min(count, index + 1)
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        ForEach(visible, id: \.self) { item in
          content(item)
            .frame(width: size.width, height: height)
            .background(Palette.paper)
            .allowsHitTesting(item == index && offset == 0 && !settling)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(item != index)
            .offset(y: CGFloat(item - index) * height + offset)
            .transition(.identity)
        }
      }
      .frame(width: size.width, height: height, alignment: .top)
      .clipped()
      if count > 1 {
        pageHint(index, height: height)
          .frame(maxWidth: .infinity).padding(.leading, layout.splitX)
          .frame(height: layout.footer)
      }
    }
    .background {
      PagePan(
        available: enabled && count > 1 && !settling, previous: index > 0, next: index + 1 < count
      ) { pan in
        track(pan, from: index, height: height)
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

  private func track(_ pan: UIPanGestureRecognizer, from index: Int, height: CGFloat) {
    guard enabled, !settling else { return }
    let distance = pan.translation(in: pan.view).y
    let next = index + (distance < 0 ? 1 : -1)
    let hasPage = (0..<count).contains(next)
    switch pan.state {
    case .began, .changed:
      offset = hasPage ? min(height, max(-height, distance)) : 0
    case .ended:
      // Project a short part of the release velocity so a quick flick can finish a page turn.
      let projected = distance + pan.velocity(in: pan.view).y * 0.15
      let threshold = min(110, height * 0.22)
      let turn = hasPage && abs(distance) >= 12 && projected * distance > 0 && abs(projected) >= threshold
      settle(from: index, to: turn ? next : index, height: height)
    case .cancelled, .failed:
      settle(from: index, to: index, height: height)
    default: break
    }
  }

  private func pageHint(_ index: Int, height: CGFloat) -> some View {
    let hint: LocalizedStringKey
    if index == 0 {
      hint = "Swipe up for more controls"
    } else if index == count - 1 {
      hint = "Swipe down to return"
    } else {
      hint = "Swipe up or down for more controls"
    }
    return Text(hint)
      .font(.caption).foregroundStyle(Palette.controlTint)
      .accessibilityLabel("Remote page")
      .accessibilityValue("Page \(index + 1) of \(count)")
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment: settle(from: index, to: index + 1, height: height)
        case .decrement: settle(from: index, to: index - 1, height: height)
        @unknown default: break
        }
      }
  }

  private func settle(from index: Int, to next: Int, height: CGFloat) {
    guard enabled, !settling, (0..<count).contains(next) else { return }
    let token = revision
    settling = true
    withAnimation(
      reduceMotion ? nil : .smooth(duration: next == index ? 0.23 : 0.32),
      completionCriteria: .removed
    ) {
      offset = CGFloat(index - next) * height
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
  }
}

/// Observe the initial touch on the whole viewport without covering native buttons,
/// source scrollers, or the volume control with a hit-testing overlay.
private struct PagePan: UIViewRepresentable {
  let available: Bool
  let previous: Bool
  let next: Bool
  let update: (UIPanGestureRecognizer) -> Void

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
      return v.y < 0 ? configuration.next : configuration.previous
    }

    func gestureRecognizer(
      _ gesture: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    @objc private func track(_ gesture: UIPanGestureRecognizer) {
      configuration?.update(gesture)
    }
  }
}
