import SwiftUI
import UIKit

extension View {
    /// Hides the tab bar when the user scrolls down and restores it when they
    /// scroll up or return near the top. Attach to the List/ScrollView.
    ///
    /// Implementation: a zero-size UIKit probe in the view's .background finds
    /// the enclosing UIScrollView and KVO-observes contentOffset. The previous
    /// PreferenceKey-on-first-row approach broke once the row was lazily
    /// recycled offscreen — the preference stopped publishing and the tab bar
    /// stuck hidden.
    func hidesTabBarOnScrollDown() -> some View {
        modifier(HidesTabBarOnScrollDown())
    }
}

private struct HidesTabBarOnScrollDown: ViewModifier {
    @State private var visibility: Visibility = .visible

    func body(content: Content) -> some View {
        content
            .toolbar(visibility, for: .tabBar)
            .background(
                ScrollDirectionObserver { direction in
                    let next: Visibility = (direction == .down) ? .hidden : .visible
                    guard next != visibility else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        visibility = next
                    }
                }
                .frame(width: 0, height: 0)
            )
    }
}

enum ScrollDirection {
    case up, down
}

private struct ScrollDirectionObserver: UIViewRepresentable {
    let onDirectionChange: (ScrollDirection) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let probe = ProbeView()
        probe.coordinator = context.coordinator
        return probe
    }

    func updateUIView(_ probe: ProbeView, context: Context) {
        context.coordinator.onDirectionChange = onDirectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDirectionChange: onDirectionChange)
    }

    final class Coordinator {
        var onDirectionChange: (ScrollDirection) -> Void
        private var observation: NSKeyValueObservation?
        private var lastY: CGFloat = 0
        /// Ignore jitter below this threshold.
        private let threshold: CGFloat = 12

        init(onDirectionChange: @escaping (ScrollDirection) -> Void) {
            self.onDirectionChange = onDirectionChange
        }

        func attach(to scrollView: UIScrollView) {
            guard observation == nil else { return }
            lastY = scrollView.contentOffset.y
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                DispatchQueue.main.async {
                    self?.handle(sv)
                }
            }
        }

        private func handle(_ sv: UIScrollView) {
            let y = sv.contentOffset.y
            let topResting = -sv.adjustedContentInset.top

            // Near the top: always show, and resync the baseline.
            if y <= topResting + 1 {
                lastY = y
                onDirectionChange(.up)
                return
            }
            // Only react to user-driven scrolling — programmatic jumps
            // (navigation restore, keyboard) shouldn't toggle the bar.
            guard sv.isTracking || sv.isDragging || sv.isDecelerating else {
                lastY = y
                return
            }
            let delta = y - lastY
            guard abs(delta) > threshold else { return }
            onDirectionChange(delta > 0 ? .down : .up)
            lastY = y
        }
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // The hosting hierarchy isn't assembled until after this runloop
            // tick — defer the search.
            DispatchQueue.main.async { [weak self] in
                self?.findAndAttach()
            }
        }

        private func findAndAttach() {
            guard let coordinator else { return }
            // The probe lives in a .background wrapper that is a SIBLING of
            // the scroll view's subtree, so climb ancestors and scan each
            // level's descendants.
            var ancestor: UIView? = superview
            var hops = 0
            while let current = ancestor, hops < 12 {
                if let scrollView = Self.firstScrollView(in: current, depth: 0) {
                    coordinator.attach(to: scrollView)
                    return
                }
                ancestor = current.superview
                hops += 1
            }
        }

        private static func firstScrollView(in view: UIView, depth: Int) -> UIScrollView? {
            if depth > 8 { return nil }
            for sub in view.subviews {
                if let sv = sub as? UIScrollView { return sv }
                if let found = firstScrollView(in: sub, depth: depth + 1) { return found }
            }
            return nil
        }
    }
}
