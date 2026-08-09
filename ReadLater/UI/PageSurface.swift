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
    /// ground shows through.
    ///
    /// **No row separators** *(Ellen, build-44 review — issue #76)*. S3 licensed
    /// a 0.5pt `Surface.divider` line between rows inside one E1 container, and
    /// the licence was spent here. Ellen struck it on sight: *"which I already
    /// didn't want but are implemented badly."* Both halves are true and they
    /// point the same way.
    ///
    /// *Implemented badly:* `.insetGrouped` insets its separators to the system
    /// text column, which has nothing to do with **our** text column —
    /// `ReadableRow` owns its own `Metric.containerPadding` and its identity
    /// tile sits ahead of the text, so the line started somewhere between the
    /// tile and the title and stopped short of the card's trailing edge. Every
    /// list in the app therefore drew a line that matched neither the row's
    /// content nor the card that contained it, and rows with and without an
    /// identity tile drew it in different places.
    ///
    /// *Didn't want them:* which makes "fix the inset" the wrong repair. The
    /// separation was already there — S2's E0→E1 value step around the card,
    /// and 24pt of ground between the text blocks of adjacent rows
    /// (`Metric.rowVerticalPadding`, top and bottom). The line answered nothing
    /// the gap was not already answering, which is N3 applied to a hairline.
    ///
    /// This is scoped to `pageList()` — the content lists. `pageForm()` keeps
    /// its separators: a settings form is a column of single-line rows with no
    /// internal padding to speak of, so the line there *is* the separation, and
    /// S3 still governs it.
    func pageList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowBackground(Surface.raised)
            .listRowSeparator(.hidden)
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
    /// value step and 16pt of gap, never by a stroke (S2) — and, since the
    /// build-44 review, separated from its neighbours by whitespace rather than
    /// by a hairline. See `pageList()`.
    func containerRow() -> some View {
        listRowBackground(Surface.raised)
            .listRowSeparator(.hidden)
    }
}
