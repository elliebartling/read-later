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
//  - **E2** structure: a 64pt line-art mark, a Lexend display-small title, one
//    sentence naming the mechanism, and — if the copy names an action — that
//    action as a prominent capsule.
//  - **E3** failure states get `Semantic.warning`; empty states get no colour
//    at all.
//
// **Placeholder marks.** E2 wants a custom 64pt line-art mark per state (I9,
// §5.3). Those are drawn in wave 5 alongside the highlight mark; until then the
// mark is an SF Symbol at the same 64pt slot, `Ink.tertiary`, at one weight —
// so the layout, spacing and copy are settled and wave 5 swaps artwork into a
// fixed hole rather than redesigning the state.

/// One empty (or failed) state, composed to E2.
struct EmptyStateView: View {
    /// The 64pt mark. An SF Symbol placeholder for §5.3's custom line art.
    let mark: String
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
            Image(systemName: mark)
                .uiGlyph(size: Font.GlyphSize.emptyStateMark)
                // E3 — emptiness gets no colour at all; failure gets exactly
                // one, on the mark.
                .foregroundStyle(isFailure ? Semantic.warning : Ink.tertiary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title)
                    // §4.3 — empty-state titles are display tier (Lexend
                    // display-small), the one place in a list surface that is
                    // not SF Pro.
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

/// **§8.3.** The prominent capsule — one per screen, and the only button
/// vocabulary an empty state may use. `Accent.fill` behind an `Accent.onFill`
/// label at the 52pt prominent tier (§7.1); no stroke (S2), no tinted plain
/// text (C1).
struct ProminentCapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Accent.onFill)
                .lineLimit(1)
                .padding(.horizontal, Metric.capsuleHorizontalPadding)
                .frame(minHeight: ControlTier.prominent.height)
                .background(Accent.fill, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// **§8.3.** The glass capsule — `.regularMaterial` plus `Surface.chromeTint`
/// at the 44pt standard tier, with an `Ink.primary` label. The quieter of the
/// two legal capsules, and the only thing a secondary action may be.
struct GlassCapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .padding(.horizontal, Metric.capsuleHorizontalPadding)
                .frame(minHeight: ControlTier.standard.height)
                .floatingChrome(in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

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
