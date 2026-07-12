import UIKit

/// Reader typefaces that resolve on iOS without bundled files. "New York" and
/// "San Francisco" are NOT name-addressable — UIFont(name:) returns nil — so
/// the system designs go through UIFontDescriptor.withDesign instead.
///
/// Bundled OFL faces (Literata, Atkinson Hyperlegible, etc.) are added in a
/// follow-up plan; this enum stays system-only.
enum ReaderFont: String, CaseIterable, Identifiable {
    case serif = "Serif"            // system serif (New York)
    case charter = "Charter"        // bundled with iOS
    case georgia = "Georgia"
    case palatino = "Palatino"
    case iowan = "Iowan Old Style"
    case sansSerif = "Sans Serif"   // system (San Francisco)

    var id: String { rawValue }
    var displayName: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case reading = "Reading"
        case sans = "Sans"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    var group: Group {
        switch self {
        case .sansSerif: return .sans
        default:         return .reading
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .serif:
            let base = UIFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .sansSerif:
            return .systemFont(ofSize: size)
        case .charter, .georgia, .palatino, .iowan:
            return UIFont(name: rawValue, size: size) ?? .systemFont(ofSize: size)
        }
    }
}
