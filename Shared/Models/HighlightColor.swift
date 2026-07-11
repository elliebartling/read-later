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
    #endif

    var displayName: String {
        rawValue.capitalized
    }
}
