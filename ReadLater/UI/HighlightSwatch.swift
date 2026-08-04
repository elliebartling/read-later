import SwiftUI
import UIKit

// The marker half of the highlight family (§2.2), and the app's ONE highlight
// colour picker (H1).
//
// Before wave 3 the same action had two pickers: a text list in the reader's
// edit menu ("Yellow / Green / Blue / Pink", showing no colour at all) and a
// swatch row in the edit sheet. The text list is deleted; this file is what
// replaced it, and it is the only place a highlight colour is offered.
//
//  - **H1** a highlight colour is always shown *in colour*, as a 20pt marker
//    circle.
//  - **Z1** the art stays 20pt; the tap target is padded to 44pt.
//  - **SH2** selection is a checkmark inside the filled swatch, never a ring.
//  - Markers carry `HighlightMarker.onMarker` glyphs, never white — white on
//    `#F9CC21` is 1.5:1.

extension HighlightColor {
    /// **Marker** — the identity value (§2.2). Saturated, because a marker
    /// never sits behind text. The paint that *does* sit behind text stays in
    /// `uiColor(darkBackground:)` and is not derived from this.
    var markerUI: UIColor {
        switch self {
        case .yellow: return HighlightMarker.yellowUI
        case .green: return HighlightMarker.greenUI
        case .blue: return HighlightMarker.blueUI
        case .pink: return HighlightMarker.pinkUI
        }
    }

    var marker: Color { Color(uiColor: markerUI) }
}

/// One marker circle. `isSelected` draws the §8.2 SH2 checkmark inside it.
struct HighlightSwatch: View {
    let color: HighlightColor
    var isSelected: Bool = false

    /// H1 — 20pt, everywhere a highlight colour is shown.
    static let diameter: CGFloat = 20

    var body: some View {
        Circle()
            .fill(color.marker)
            .frame(width: Self.diameter, height: Self.diameter)
            .overlay {
                if isSelected {
                    // I2 — one weight, one scale, sized to the swatch's
                    // `.caption2` chip tier (§4.3).
                    Image(systemName: "checkmark").uiGlyph(size: 11)
                        .foregroundStyle(HighlightMarker.onMarker)
                }
            }
    }
}

/// The picker. Four swatches, one selection, nothing else — the only highlight
/// colour control in the app.
struct HighlightSwatchRow: View {
    @Binding var selection: HighlightColor
    /// Called after `selection` is written, for callers that persist a
    /// last-used colour or fire the §10 `.selection` haptic.
    var onPick: ((HighlightColor) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    selection = color
                    onPick?(color)
                } label: {
                    HighlightSwatch(color: color, isSelected: selection == color)
                        // Z1 — invisible padding to the 44pt floor, not bigger
                        // art.
                        .frame(
                            width: ControlTier.hitTarget,
                            height: ControlTier.hitTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
