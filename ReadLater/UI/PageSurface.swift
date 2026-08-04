import SwiftUI

// One page surface, one container surface — the whole system (§3, S1).
//
// Before wave 1 the app had three page backgrounds across four tabs: Library,
// Feeds and Search were `.plain` on `systemBackground`, Highlights was the
// default grouped style, and Settings was a `Form`. Switching tabs changed the
// page out from under you for no reason anybody had decided.
//
// `pageList()` is now the only way a list is styled. There is no second one:
// if a screen needs something else, that is a rule change, not a local choice.

extension View {
    /// **S1.** Every `List` in the app: `.insetGrouped` containers (E1) sitting
    /// on `Surface.ground` (E0). The system list background is hidden so the
    /// ground shows through, and the one legal line — the row separator inside
    /// a container (S3) — is tinted to `Surface.divider`.
    func pageList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowBackground(Surface.raised)
            .listRowSeparatorTint(Surface.divider)
            .pageBackground()
    }

    /// **Layer 0 only.** The sidebar is not a destination list — it is the
    /// ground floor the whole app sits on — so it is the one list in the app
    /// that is NOT `pageList()`.
    ///
    /// Ellen, reviewing build 43 against Reeder and Craft: the sidebar "may
    /// have too much layering: let's get closer to Reeder and Craft." An
    /// inset-grouped sidebar puts a floating `Surface.raised` card under every
    /// section, then a selection pill *inside* that card, on top of the peel
    /// card that is already floating over the sidebar — surface on surface on
    /// surface, three deep, for a list of eight rows. Both references are flat:
    /// headers and rows sit directly on the ground and whitespace does the
    /// separating that the cards were doing.
    ///
    /// So: no row containers, no separators, no section cards. The selection
    /// wash (`Accent.muted`, A1) is the only fill in the list, and it lands
    /// directly on `Surface.ground`. The peel card above keeps its elevation —
    /// the layer model is not what Ellen was objecting to.
    func sidebarList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .pageBackground()
    }

    /// **S1** for `Form`. Forms are already grouped, so they only need the
    /// system background swapped for our ground and their rows swapped for our
    /// container fill.
    func pageForm() -> some View {
        scrollContentBackground(.hidden)
            .listRowBackground(Surface.raised)
            .listRowSeparatorTint(Surface.divider)
            .pageBackground()
    }

    /// The E0 ground, for surfaces that aren't a `List` (forms, scroll views,
    /// full-screen states). Extends under the bars so a bounce never reveals
    /// the system background beneath.
    func pageBackground() -> some View {
        background(Surface.ground.ignoresSafeArea())
    }

    /// One row in a `sidebarList()`: no fill, no separator, one horizontal
    /// inset (the audit found four different left insets in one sidebar list),
    /// and `topGap` of whitespace above it where a group begins. The gap is a
    /// list-row inset rather than padding inside the row, so the selection wash
    /// stays the height of the row and does not swell into the gap.
    func sidebarRow(topGap: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(
            top: topGap, leading: Metric.containerPadding,
            bottom: 0, trailing: Metric.containerPadding
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// **E1.** A row inside a `pageList()`. Separated from the ground by the
    /// value step and 16pt of gap, never by a stroke (S2).
    func containerRow() -> some View {
        listRowBackground(Surface.raised)
    }
}
