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

    /// **E1.** A row inside a `pageList()`. Separated from the ground by the
    /// value step and 16pt of gap, never by a stroke (S2).
    func containerRow() -> some View {
        listRowBackground(Surface.raised)
    }
}
