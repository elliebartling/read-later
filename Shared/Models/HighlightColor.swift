import SwiftUI

enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow, green, blue, pink

    var id: String { rawValue }

    var swiftUIColor: Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// RGB components of the identity marker color.
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
