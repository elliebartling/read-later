import SwiftUI

// §8.3 — seven button vocabularies became three.
//
// The audit counted seven ways this app drew a button: `.borderedProminent`
// capsules, `.borderless` tinted text, bare tinted `Button` labels inside
// forms, a `Surface.control`-filled circle in the sidebar header, plain rows
// pretending to be buttons, toolbar glyphs, and the reader's own capsule. This
// file is the whole legal set:
//
// | Vocabulary          | Shape                                              | Use |
// |---------------------|----------------------------------------------------|-----|
// | **Glass circle**    | 44pt circle, system glass (`floatingChrome`)       | Every nav-bar and floating single action. |
// | **Glass capsule**   | 44pt tall, system glass (`floatingChrome`)         | Multi-glyph clusters and the audio capsule (§7.3). |
// | **Prominent capsule** | `Accent.fill` / `Accent.onFill`, 52pt            | The one primary action on a screen. Max one. |
//
//  - **C1.** Plain tinted text as a button is banned. The constitution names
//    the offenders — "Export all articles" and "Save key" — and gives the two
//    legal outs: a prominent capsule, or a **row with disclosure**. `FormRowButton`
//    is that second out, and it is what most of Settings became: a row is not a
//    fourth vocabulary, it is the list-row grammar (§8.1) doing the work.
//  - **A1/A2.** Interactive colour reaches these only through `Accent.*`, and
//    `onFill` is never hardcoded to white or black.
//  - **S2.** No strokes on any of them. Separation is material and value.
//  - **S4.** The two glass vocabularies are *actually glass* — the system
//    material, translucent, never a tint painted over a material until the
//    blur is gone. See `floatingChrome(in:)`.

/// **§8.3.** The prominent capsule — `Accent.fill` behind an `Accent.onFill`
/// label at the 52pt prominent tier (§7.1). One per screen, maximum.
struct ProminentCapsuleButton: View {
    let title: String
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Accent.onFill)
                .lineLimit(1)
                // T8 — a confirm label can carry a count; it never wraps.
                .fixedSize(horizontal: fillsWidth ? false : true, vertical: false)
                .padding(.horizontal, Metric.capsuleHorizontalPadding)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(minHeight: ControlTier.prominent.height)
                .background(Accent.fill, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// **§8.3.** The glass capsule — the system glass material at the 44pt standard
/// tier, with an `Ink.primary` label. The quieter of the two legal capsules,
/// and the only thing a secondary action may be.
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

/// **§8.3.** The glass circle — a 44pt circle of the system glass material
/// carrying one `Ink.primary` glyph (I2/I4). Every floating single action wears
/// this; the sidebar header's add button used to wear a `Surface.control` fill
/// that appeared nowhere else in the app.
///
/// Wraps a `Menu` as readily as a `Button` — pass the presentation through
/// `label`, which is why this is a container rather than a `Button` subtype.
struct GlassCircle<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .uiGlyph()
            .foregroundStyle(Ink.primary)
            .frame(
                width: ControlTier.standard.height,
                height: ControlTier.standard.height
            )
            .floatingChrome(in: .circle)
            .contentShape(.circle)
    }
}

/// **C1's second out** — a form/list row that performs an action, drawn as a
/// row rather than as tinted text. The label is `Ink.primary` (a row title,
/// §4.3), the state or disclosure is trailing, and nothing is tinted.
///
/// This is deliberately not a fourth button vocabulary: it is `ReadableRow`'s
/// grammar applied to a settings row, which is why a screen may hold several
/// without breaking "max one prominent capsule".
struct FormRowButton: View {
    let title: String
    /// Trailing state, `Ink.secondary` — "Chosen", a key preview, a count.
    var value: String?
    /// Draws the system disclosure chevron. Off for a row that commits an
    /// action in place (Save key) and on for one that opens something.
    var showsDisclosure = false
    /// A destructive row takes `Semantic.destructive` on its **label** — the
    /// one place the row grammar admits colour, because no text field carries
    /// "this removes something".
    var isDestructive = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(isDestructive ? Semantic.destructive : Ink.primary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .uiGlyph(size: Font.GlyphSize.caption)
                        .foregroundStyle(Ink.tertiary)
                }
            }
            .frame(minHeight: ControlTier.hitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
