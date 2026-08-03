import SwiftUI

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
