import UIKit

/// Reader structure that BOTH readers must agree on.
///
/// AGENTS.md's two-readers rule exists because a typography fix has landed in
/// one reader and silently regressed in the other before. The plain reader
/// (`HighlightableTextView`) renders `plainText` as one text view and gets its
/// structure from paragraph-style attributes over verified ranges; the block
/// reader (`Features/Reader/Blocks/`) renders one text view per block and gets
/// it from per-block styles and SwiftUI spacing. Different mechanisms, one set
/// of numbers — which is what this type is.
///
/// Everything here is derived from the user's own typography settings (T1: no
/// UI agent hardcodes reader body metrics), so it scales with them.
enum ReaderTypography {

    /// **Hanging indent.** A marker-baked list item's continuation lines are
    /// indented by exactly the marker's rendered width, so a wrapped line
    /// aligns under the item's *text* rather than under its bullet. The audit
    /// called the missing version "the most visible defect in the type system"
    /// — multi-line list items lost their shape entirely.
    static func markerWidth(_ prefix: String, font: UIFont) -> CGFloat {
        guard !prefix.isEmpty else { return 0 }
        return ceil((prefix as NSString).size(withAttributes: [.font: font]).width)
    }

    /// **List grouping.** Item spacing was equal to paragraph spacing, so a
    /// five-item list read as five paragraphs. Items sit at a fraction of it
    /// instead, which is what makes the list read as one object — and it stays
    /// proportional to the reader's own paragraph-spacing setting rather than
    /// becoming a second hardcoded number.
    static func listItemSpacing(paragraphSpacing: CGFloat) -> CGFloat {
        max(2, (paragraphSpacing * 0.35).rounded())
    }

    /// **Inline code.** Monospaced, slightly smaller so its x-height matches
    /// the body face, on the same wash the block-level code panel uses — so a
    /// `snippet` in a sentence and a fenced block read as the same material.
    static func inlineCodeFont(bodySize: CGFloat) -> UIFont {
        .monospacedSystemFont(ofSize: bodySize * 0.92, weight: .regular)
    }

    /// The wash behind inline code. Derived from the reader theme's own ink, so
    /// it works on all eight papers (T1/T2) instead of being a fixed grey that
    /// would fight sepia.
    static func inlineCodeBackground(foreground: UIColor) -> UIColor {
        foreground.withAlphaComponent(0.055)
    }
}
