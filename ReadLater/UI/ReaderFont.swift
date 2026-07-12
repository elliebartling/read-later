import UIKit

/// Reader typefaces: iOS system faces plus bundled OFL variable fonts
/// (registered via UIAppFonts; files under ReadLater/Resources/Fonts).
///
/// "New York" and "San Francisco" are NOT name-addressable — UIFont(name:)
/// returns nil — so the system designs go through UIFontDescriptor.withDesign.
/// Bundled faces resolve by PostScript name (taken from each file's name
/// table) and fall back to the system font if registration ever fails, so a
/// missing file degrades gracefully instead of crashing.
enum ReaderFont: String, CaseIterable, Identifiable {
    // Reading
    case serif = "Serif"            // system serif (New York)
    case literata = "Literata"      // bundled OFL
    case charter = "Charter"        // bundled with iOS
    case georgia = "Georgia"
    case palatino = "Palatino"
    case iowan = "Iowan Old Style"
    // Accessibility
    case atkinson = "Atkinson Hyperlegible"  // bundled OFL (Next)
    case lexend = "Lexend"                   // bundled OFL
    // Sans
    case sansSerif = "Sans Serif"   // system (San Francisco)
    case inter = "Inter"            // bundled OFL
    case geist = "Geist"            // bundled OFL

    var id: String { rawValue }
    var displayName: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case reading = "Reading"
        case accessibility = "Accessibility"
        case sans = "Sans"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    var group: Group {
        switch self {
        case .atkinson, .lexend:
            return .accessibility
        case .sansSerif, .inter, .geist:
            return .sans
        default:
            return .reading
        }
    }

    /// PostScript name for bundled faces (nil for system-resolved ones).
    private var postScriptName: String? {
        switch self {
        case .literata: return "Literata-Regular"
        case .atkinson: return "AtkinsonHyperlegibleNext-Regular"
        case .lexend:   return "Lexend-Regular"
        case .inter:    return "Inter-Regular"
        case .geist:    return "Geist-Regular"
        default:        return nil
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        if let psName = postScriptName {
            return UIFont(name: psName, size: size) ?? .systemFont(ofSize: size)
        }
        switch self {
        case .serif:
            let base = UIFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .sansSerif:
            return .systemFont(ofSize: size)
        default:
            return UIFont(name: rawValue, size: size) ?? .systemFont(ofSize: size)
        }
    }
}
