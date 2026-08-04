import SwiftUI

// §5.1 — SF Symbol usage, normalised (I2–I4).
//
// The audit's "clinical" verdict is mostly a *usage* problem, not an artwork
// problem: the app mixed `.title3` glyphs beside `.caption` labels, `.bold`
// beside `.regular`, filled beside outline inside one control group, and a
// couple of multicolour symbols. This file is the one place a symbol's weight,
// scale and rendering mode is decided, so a call site can no longer invent its
// own.
//
//  - **I2** every symbol renders `.medium` weight at `.medium` scale, sized to
//    the adjacent text's optical size. The size comes from a §7.1 control tier
//    (or an explicit optical size when the glyph sits beside body/caption text).
//  - **I3** fill is semantic, never decorative. Outline = available/inactive,
//    filled = active/selected/on, never mixed inside one control group. The one
//    exception is transport controls, where filled is the shape itself.
//  - **I4** symbols are monochrome `Ink.*` or `Accent.primary`. `.hierarchical`,
//    `.palette` and multicolour are banned — multicolour SF Symbols are the
//    strongest "unstyled iOS app" signal there is, so the mode is pinned here
//    rather than left to the system default.
//
// §5.4 note: when the third-party set lands, only the *artwork* changes. Every
// call site already asks for "a glyph at this optical size", so the migration
// is a change to this file plus the symbol names, not a redesign.

extension View {
    /// **I2 / I4.** A system-verb glyph at one weight, one scale, one
    /// rendering mode, sized to a §7.1 control tier.
    func uiGlyph(_ tier: ControlTier = .standard) -> some View {
        uiGlyph(size: tier.glyph)
    }

    /// **I2 / I4.** A glyph sized to the optical size of the text beside it —
    /// for the few places a glyph sits inline in a label run rather than inside
    /// a control (an empty state's mark, R7's warning in a meta line).
    func uiGlyph(size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .medium))
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
    }
}

extension Font {
    /// Optical sizes glyphs are matched to when they sit beside text rather
    /// than inside a control. Kept here so "the size of the adjacent text"
    /// is a value and not a guess at each call site.
    enum GlyphSize {
        /// Beside `.caption` (12pt) — meta lines.
        static let caption: CGFloat = 12
        /// Beside `.subheadline` (15pt).
        static let subheadline: CGFloat = 15
        /// Beside `.body` (17pt).
        static let body: CGFloat = 17
        /// The empty-state mark (§8.5 E2).
        static let emptyStateMark: CGFloat = 64
    }
}
