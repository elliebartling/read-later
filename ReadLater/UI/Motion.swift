import SwiftUI
import UIKit

// §10 motion, in one place.
//
// The constitution names four classes and one degradation rule:
//
//  - **M3** "Reduce Motion is not optional. Every Standard and Attention
//    animation degrades to a 0.15s crossfade. Springs are wrapped so this is
//    one check, not one per call site." `Motion.resolve` is that wrapper.
//  - **M2** no animation exceeds 0.4s; no curve outside the table below.
//
// Navigation (push, pop, sheet present) is deliberately absent: it is the
// system default and is never overridden.

enum Motion {
    /// Tint changes, checkmarks, toggle states, glyph swaps.
    static let micro = Animation.easeOut(duration: 0.18)
    /// Chrome reveal/hide, row insert/remove, capsule reshaping, sheet
    /// content, the navigation peel. Damping 0.88 settles without overshoot.
    static let standard = Animation.spring(response: 0.34, dampingFraction: 0.88)
    /// The four playful moments in §9 only — the one curve with any overshoot.
    static let attention = Animation.spring(response: 0.28, dampingFraction: 0.72)
    /// **M3.** What every Standard and Attention animation becomes when the
    /// reader has asked the system for less motion.
    static let reduced = Animation.easeInOut(duration: 0.15)

    /// **M3**, as one call. Pass `@Environment(\.accessibilityReduceMotion)`.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

// MARK: - M3 as a modifier

/// **M3** without threading `@Environment(\.accessibilityReduceMotion)` through
/// every view that animates.
///
/// Before wave 5 the wrapper existed but only `SidebarShell` used it: the
/// reader ran its own `.spring(response: 0.4, dampingFraction: 0.85)` — a curve
/// that is not in the §10 table at all — and the image viewer, the block reader
/// and the site-login sheet each animated with a bare system default. Every one
/// of those ignored Reduce Motion. These modifiers are the fix, and they are
/// the only way a view in this app should reach for a curve.
extension View {
    /// A **Standard** animation (chrome reveal, row insert, capsule reshaping,
    /// sheet content), degraded to a crossfade under Reduce Motion.
    func motionStandard(value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: Motion.standard, value: value))
    }

    /// A **Micro** animation (tint changes, checkmarks, toggle states, glyph
    /// swaps). Micro is already a sub-0.2s fade, so M3 leaves it alone.
    func motionMicro(value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: Motion.micro, value: value))
    }

    /// An **Attention** animation. §9 budgets these to four moments; nothing
    /// else in the app may call this.
    func motionAttention(value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: Motion.attention, value: value))
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - M4 haptics

/// **M4.** "Haptics pair with the Attention class only: `.success` on save,
/// `.selection` on highlight-colour change. Nowhere else."
///
/// Centralised so the rule is checkable by grep: two call sites are legal and
/// a third is a violation, which is not something you can see when every view
/// builds its own `UIImpactFeedbackGenerator`.
@MainActor
enum Haptic {
    /// A save landed. Pairs with §9's save-confirmation moment.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The reader picked a different highlight colour.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
