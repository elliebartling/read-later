import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// The app's core taxonomy (§2.2), split into the two roles the design
/// language separates and this type used to conflate:
///
/// - **Paint** — what sits *behind text*, `uiColor(darkBackground:)`. Protected
///   work: the multiply-on-light / screen-on-dark composite below keeps body
///   text legible on all eight reader papers and must never be replaced with a
///   plain alpha.
/// - **Marker** — the identity chip (swatches, picker circles, the Highlights
///   rail). Saturated, precisely because a marker never sits behind text. It
///   lives in the app's token file as `HighlightColor.marker`
///   (`ReadLater/UI/HighlightSwatch.swift`), not here, because `Shared/` also
///   compiles into the extensions and they have no design-token layer.
///
/// Nothing may render `rgb` directly as an identity colour — that pastel is a
/// paint input, and using it as a swatch is what made the app's own taxonomy
/// look washed out in the audit (theme 7).
enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow, green, blue, pink

    var id: String { rawValue }

    /// RGB components the *paint* composites from. Deliberately private: the
    /// identity value is `marker`.
    private var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .yellow: return (1.0, 0.93, 0.55)
        case .green:  return (0.72, 0.94, 0.72)
        case .blue:   return (0.68, 0.84, 1.0)
        case .pink:   return (1.0, 0.75, 0.85)
        }
    }

    #if canImport(UIKit)
    /// Opaque highlight paint tuned to the page darkness.
    /// - Light pages: the marker multiplied onto near-white at 0.55 strength
    ///   (matches the old translucent look, but opaque so it composites cleanly
    ///   over sepia/paper too).
    /// - Dark pages: a screen-lifted band, brighter than the page so the text
    ///   underneath stays readable, at 0.40 strength — 0.55 read as glowing on
    ///   dark/slate papers.
    func uiColor(darkBackground: Bool) -> UIColor {
        let (r, g, b) = rgb
        if darkBackground {
            let base: CGFloat = 0.16   // nominal dark page level
            func screen(_ m: CGFloat) -> CGFloat { 1 - (1 - base) * (1 - m * 0.40) }
            return UIColor(red: screen(r), green: screen(g), blue: screen(b), alpha: 1)
        } else {
            let page: CGFloat = 0.99   // nominal light page level
            func multiply(_ m: CGFloat) -> CGFloat { page * (0.45 + 0.55 * m) }
            return UIColor(red: multiply(r), green: multiply(g), blue: multiply(b), alpha: 1)
        }
    }
    #endif

    var displayName: String {
        rawValue.capitalized
    }
}
