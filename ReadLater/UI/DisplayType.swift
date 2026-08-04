import SwiftUI
import UIKit

/// §4.2 / T4–T6 — the display tier.
///
/// "SF Pro for everything under 28pt; one bundled face for display type at
/// 28pt and above." The display face is **Lexend**, weight 600, `-0.5`
/// tracking; it is already bundled for the reader's face catalogue
/// (`project.yml` → `UIAppFonts`), so this costs no new dependency.
///
/// - **T5** display type is still Dynamic Type: `Font.custom(_:size:relativeTo:)`,
///   never a fixed size.
/// - **T6** if Lexend fails to register, the tier falls back to SF Pro `.bold`
///   silently — never a layout change, never a crash.
enum DisplayType {
    /// PostScript name of the bundled variable face.
    private static let faceName = "Lexend-Regular"

    /// Whether the bundled display face registered. Resolved once.
    static let isAvailable = UIFont(name: faceName, size: 17) != nil

    /// A display-tier font. `size` must be ≥ 28 (T4); below that the app uses
    /// SF Pro and this type has nothing to say.
    static func font(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        guard isAvailable else {
            return .system(style, design: .default).weight(.bold)
        }
        return .custom(faceName, size: size, relativeTo: style).weight(.semibold)
    }

    /// §4.3 — screen titles, the sidebar header, empty-state titles.
    static var display: Font { font(size: 34, relativeTo: .largeTitle) }
    /// §4.3 — sheet titles, bento tile leads.
    static var displaySmall: Font { font(size: 28, relativeTo: .title2) }

    /// T4's tracking. Applied by the call site because `Font` cannot carry it.
    static let tracking: CGFloat = -0.5
}

extension View {
    /// Display tier: Lexend 600 at `-0.5` tracking, or SF Pro bold if the face
    /// is missing (T6).
    func displayType(_ font: Font = DisplayType.display) -> some View {
        self.font(font)
            .tracking(DisplayType.isAvailable ? DisplayType.tracking : 0)
    }
}
