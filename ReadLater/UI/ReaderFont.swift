import UIKit

/// Reader typefaces that actually resolve on iOS. "New York" and
/// "San Francisco" are NOT name-addressable — UIFont(name:) returns nil and
/// silently falls back to sans — so the system designs go through
/// UIFontDescriptor.withDesign instead.
enum ReaderFont: String, CaseIterable, Identifiable {
    case serif = "Serif"            // system serif (New York)
    case sansSerif = "Sans Serif"   // system (San Francisco)
    case georgia = "Georgia"
    case palatino = "Palatino"
    case iowan = "Iowan Old Style"

    var id: String { rawValue }
    var displayName: String { rawValue }

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
        case .georgia, .palatino, .iowan:
            return UIFont(name: rawValue, size: size) ?? .systemFont(ofSize: size)
        }
    }
}
