import SwiftUI

// §8.5 — the empty-state template (E1–E3).
//
// `Site Logins` is the template the constitution names: centred, and it
// explains the *mechanism* that would fill the void rather than naming the
// void. Before this the app had three placements for the same component —
// Library's sat as a `List` row so it hung high under the title, Feeds' sat as
// a row inside the list, Search's was a centred `.overlay` — and each used a
// different type scale.
//
//  - **E1** the empty state is always an `.overlay` on the scroll view,
//    centred in the viewport. Never a list row, never boxed in a card.
//  - **E2** structure: a 64pt line-art mark, a display-small title, one
//    sentence naming the mechanism, and — if the copy names an action — that
//    action as a prominent capsule.
//  - **E3** failure states get `Semantic.warning`; empty states get no colour
//    at all.
//
// **The marks are real now (wave 5).** Wave 2 shipped this template with SF
// Symbols standing in the 64pt slot, precisely so the layout, spacing and copy
// could settle first and the artwork could drop into a fixed hole. `Mark` (§5.3,
// `Marks.swift`) is that artwork: custom line art at I9's one spec, 2pt on a
// 24pt grid. No empty state renders an SF Symbol any more — a system symbol
// blown up to 64pt is exactly what Ellen's "feels unbranded" note was about.

/// One empty (or failed) state, composed to E2.
struct EmptyStateView: View {
    /// The 64pt mark — custom line art (§5.3), never a system symbol.
    let mark: Mark
    let title: String
    /// One sentence naming the mechanism that fills this void.
    let message: String
    /// **E3.** A failure, not an emptiness — the mark takes `Semantic.warning`.
    var isFailure = false
    /// **E2.** Present only when the copy names an action.
    var actionTitle: String?
    var action: (() -> Void)?
    /// A second way out, for the one state that genuinely has two (a failed
    /// parse can retry *or* leave for the browser). §8.3 allows exactly one
    /// prominent capsule per screen, so this takes the glass-capsule
    /// vocabulary rather than a second prominent one — or a tinted text
    /// button, which C1 bans outright.
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            MarkView(mark: mark)
                // E3 — emptiness gets no colour at all; failure gets exactly
                // one, on the mark.
                .foregroundStyle(isFailure ? Semantic.warning : Ink.tertiary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title)
                    // §4.3 — empty-state titles are display tier. Since
                    // Ellen's review of PR #73 that tier is system type; the
                    // modifier stays so a future type pass has one seam.
                    .displayType(DisplayType.displaySmall)
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.center)
            }
            if actionTitle != nil || secondaryActionTitle != nil {
                VStack(spacing: 10) {
                    if let actionTitle, let action {
                        ProminentCapsuleButton(title: actionTitle, action: action)
                    }
                    if let secondaryActionTitle, let secondaryAction {
                        GlassCapsuleButton(title: secondaryActionTitle, action: secondaryAction)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, Metric.screenMargin)
        // E1 — centred in the viewport, not pinned under the title.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// The two capsule vocabularies an empty state uses moved to
// `ButtonVocabulary.swift` in wave 5, alongside the glass circle and the
// C1-compliant form row, so §8.3's whole legal set lives in one file.

extension View {
    /// **E1.** Hangs an empty state over a scroll view, centred in the
    /// viewport. The list itself keeps rendering (so a pull-to-refresh still
    /// works); the state floats over it.
    @ViewBuilder
    func emptyStateOverlay(_ state: EmptyStateView?) -> some View {
        overlay {
            if let state { state }
        }
    }
}
