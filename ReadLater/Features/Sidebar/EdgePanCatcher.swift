import SwiftUI
import UIKit

/// An edge-started pan, installed on the hosting view and exposed to SwiftUI.
///
/// Why UIKit rather than a SwiftUI `DragGesture` on an edge strip: the peel has
/// to behave like the system back gesture, and an overlay strip cannot.
///
/// - A SwiftUI overlay swallows taps on the leading 20pt of every row and
///   fights the leading `swipeActions` in the feed lists.
/// - A recognizer on the hosting view arbitrates with the list's scroll pan
///   the way UIKit intends: it only begins for a touch that starts inside the
///   edge zone *and* moves horizontally, so scrolling near the bezel still
///   scrolls, and when the peel does begin the scroll view is cancelled.
///
/// Why a plain `UIPanGestureRecognizer` with an explicit edge test rather than
/// `UIScreenEdgePanGestureRecognizer`: the screen-edge recognizer only accepts
/// touches the window marks as system-edge gestures, which synthetic HID events
/// never are — the same reason the *system's* interactive pop cannot be driven
/// in the simulator harness. Filtering an ordinary pan gives identical feel,
/// makes the edge zone ours to state (`edgeWidth`), and keeps the gesture
/// verifiable on a simulator.
///
/// The recognizer is attached to the top-most view under the window — the root
/// hosting view — so it sees touches anywhere in the shell, and so a presented
/// sheet (its own view controller, above this one) never reaches it.
struct EdgePanCatcher: UIViewRepresentable {
    enum Edge {
        case leading, trailing
    }

    /// Which edge starts the pan.
    let edge: Edge
    /// Recognition is switched off rather than removed, so the reader keeps the
    /// system's interactive pop for itself (`path` non-empty ⇒ disabled).
    var isEnabled: Bool
    /// Live horizontal translation, in points.
    var onChanged: (CGFloat) -> Void
    /// Final translation and horizontal velocity (points/second).
    var onEnded: (CGFloat, CGFloat) -> Void

    /// How far in from the edge a touch may start. 20pt is UIKit's own
    /// screen-edge width.
    static let edgeWidth: CGFloat = 20

    func makeUIView(context: Context) -> UIView {
        let view = HostFinderView()
        // Zero-size and never hit-tested: this view is a handle onto UIKit,
        // not a participant in layout or touch delivery.
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.isEnabled = isEnabled
        if let host = (uiView as? HostFinderView)?.hostView {
            context.coordinator.attach(to: host)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(edge: edge) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let edge: Edge
        private var recognizer: UIPanGestureRecognizer?
        private weak var attachedView: UIView?
        /// Where the current touch went down, captured before the pan begins.
        private var startLocation: CGPoint = .zero

        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        var isEnabled = true {
            didSet { recognizer?.isEnabled = isEnabled }
        }

        init(edge: Edge) {
            self.edge = edge
        }

        func attach(to view: UIView) {
            guard attachedView !== view else { return }
            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.delegate = self
            pan.isEnabled = isEnabled
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            recognizer = pan
            attachedView = view
        }

        func detach() {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedView = nil
        }

        @objc private func handle(_ gesture: UIPanGestureRecognizer) {
            let view = gesture.view
            let translation = gesture.translation(in: view).x
            switch gesture.state {
            case .changed:
                onChanged(translation)
            case .ended:
                onEnded(translation, gesture.velocity(in: view).x)
            case .cancelled, .failed:
                // No velocity: whatever was travelled decides, which for a
                // cancelled drag is almost always "snap back".
                onEnded(translation, 0)
            default:
                break
            }
        }

        /// Half the edge contract: the touch must go down inside the edge zone.
        /// Rejecting here means the recognizer never sees touches that start
        /// anywhere else, so it cannot interfere with taps, scrolls or row
        /// swipes in the other 380pt of the screen.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = gestureRecognizer.view else { return false }
            let location = touch.location(in: view)
            startLocation = location
            switch edge {
            case .leading:
                return location.x <= EdgePanCatcher.edgeWidth
            case .trailing:
                return location.x >= view.bounds.width - EdgePanCatcher.edgeWidth
            }
        }

        /// The other half: the movement must be horizontal and away from that
        /// edge. Anything else — a scroll, a diagonal — is somebody else's
        /// gesture.
        ///
        /// The comparison uses the touch-down point captured above rather than
        /// `translation(in:)`, which is still zero here: a pan reports no
        /// translation until it has actually begun, so testing it at this point
        /// rejects every gesture. (That bug is why this is spelled out.)
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let view = gesture.view else { return false }
            let current = gesture.location(in: view)
            let dx = current.x - startLocation.x
            let dy = current.y - startLocation.y
            guard abs(dx) > abs(dy) else { return false }
            return edge == .leading ? dx > 0 : dx < 0
        }

        /// The list scrolls or the card peels — never both at once.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }

    // MARK: - Host lookup

    /// Finds the top-most view beneath the window so the recognizer can be
    /// installed where it sees the whole shell.
    private final class HostFinderView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let hostView else { return }
            coordinator?.attach(to: hostView)
        }

        var hostView: UIView? {
            guard let window else { return nil }
            var candidate: UIView = self
            while let parent = candidate.superview, parent !== window {
                candidate = parent
            }
            return candidate === self ? nil : candidate
        }
    }
}
