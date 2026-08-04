import SwiftUI

/// The display tier — **system type**.
///
/// §4.2 / T4–T6 originally put a bundled face (Lexend) on everything ≥28pt to
/// answer Ellen's "feels unbranded" note. Her review of PR #73 overruled it:
///
/// > "Lexend is not a brand font… either a full typography pad with a real
/// > perspective, or keep everything system."
///
/// So the display tier is San Francisco, bold, at the matching text style, and
/// no UI surface loads a custom face. This type survives only as the *name* of
/// the tier — the one place a screen title, a sheet title or an empty-state
/// title is declared — so a future typography pass has a single seam to change
/// instead of a scatter of `.font(.largeTitle)` calls.
///
/// Dynamic Type still applies, and now trivially: a text style scales itself.
///
/// (Lexend is still bundled and still offered in the reader's *reading*-face
/// catalogue, `ReaderFont`. That is a user-chosen body face for article text,
/// not a brand face for chrome, and the audit graded that catalogue good.)
enum DisplayType {
    /// §4.3 — screen titles, the sidebar header, empty-state titles.
    static var display: Font { .largeTitle.weight(.bold) }
    /// §4.3 — sheet titles, bento tile leads.
    static var displaySmall: Font { .title2.weight(.bold) }
}

extension View {
    /// Display tier. Kept as a modifier rather than a bare `.font(...)` so the
    /// tier stays greppable and a future type pass has one place to land.
    func displayType(_ font: Font = DisplayType.display) -> some View {
        self.font(font)
    }
}
