import SwiftUI

enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow, green, blue, pink

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.93, blue: 0.55)
        case .green:  return Color(red: 0.72, green: 0.94, blue: 0.72)
        case .blue:   return Color(red: 0.68, green: 0.84, blue: 1.0)
        case .pink:   return Color(red: 1.0, green: 0.75, blue: 0.85)
        }
    }

    #if canImport(UIKit)
    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1.0)
        case .green:  return UIColor(red: 0.72, green: 0.94, blue: 0.72, alpha: 1.0)
        case .blue:   return UIColor(red: 0.68, green: 0.84, blue: 1.0, alpha: 1.0)
        case .pink:   return UIColor(red: 1.0, green: 0.75, blue: 0.85, alpha: 1.0)
        }
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

    /// Opaque highlight paint tuned to the page darkness.
    /// - Light pages: the marker multiplied onto near-white at 0.55 strength
    ///   (matches the old translucent look, but opaque so it composites cleanly
    ///   over sepia/paper too).
    /// - Dark pages: a screen-lifted mid band, brighter than the page so the
    ///   text underneath stays readable.
    func uiColor(darkBackground: Bool) -> UIColor {
        let (r, g, b) = rgb
        if darkBackground {
            let base: CGFloat = 0.16   // nominal dark page level
            func screen(_ m: CGFloat) -> CGFloat { 1 - (1 - base) * (1 - m * 0.55) }
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
