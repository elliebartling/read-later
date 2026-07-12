#if canImport(UIKit)
import UIKit

extension ReaderTheme {
    var foreground: UIColor {
        switch self {
        case .light:      return UIColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1)
        case .dark:       return UIColor(white: 0.92, alpha: 1)
        case .sepia:      return UIColor(red: 0.35, green: 0.24, blue: 0.14, alpha: 1)
        case .darkGray:   return UIColor(white: 0.95, alpha: 1)
        case .mediumGray: return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .slate:      return UIColor(red: 0.85, green: 0.89, blue: 0.95, alpha: 1)
        case .paper:      return UIColor(red: 0.17, green: 0.14, blue: 0.11, alpha: 1)
        case .forest:     return UIColor(red: 0.88, green: 0.94, blue: 0.87, alpha: 1)
        }
    }

    var background: UIColor {
        switch self {
        case .light:      return UIColor(white: 0.99, alpha: 1)
        case .dark:       return UIColor(white: 0.06, alpha: 1)
        case .sepia:      return UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1)
        case .darkGray:   return UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1)
        case .mediumGray: return UIColor(red: 0.82, green: 0.82, blue: 0.839, alpha: 1)
        case .slate:      return UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1)
        case .paper:      return UIColor(red: 0.961, green: 0.941, blue: 0.909, alpha: 1)
        case .forest:     return UIColor(red: 0.102, green: 0.180, blue: 0.110, alpha: 1)
        }
    }
}
#endif
