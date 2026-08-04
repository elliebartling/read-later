import SwiftUI
import UIKit

// The design language's palette and sizing standards, in code.
//
// Source of truth: `docs/design-language.md` §2 (palette), §3 (surfaces &
// glass), §7 (sizing). Every value below is quoted from that document; if a
// value here disagrees with the document, the document wins and this file is
// the bug.
//
// Rules this file exists to make enforceable:
//
//  - **N7** every token is defined for BOTH schemes. There is no light-only
//    or dark-only token; `UIColor.scheme` refuses to build one.
//  - **A1** no view may reference `Ink.*` or `Surface.*` for an interactive
//    role (selection, activation, links, unread). Those go through `Accent.*`.
//  - **A2** `Accent.onFill` is never hardcoded to white or black.
//  - **A3** nothing may depend on `Accent.*` currently resolving to a neutral.
//    v1 binds the accent to ink (§2.3); a later rebind must be a rebind, not
//    a repaint, so never substitute `Ink.primary` "because it's the same".
//
// UIKit values are the primitives (`…UI`) because the reader is TextKit and
// needs `UIColor`; the SwiftUI `Color` is derived from the same instance, so
// the two can never drift.

// MARK: - Hex plumbing

extension UIColor {
    /// `0xRRGGBB` → colour. Alpha is separate so the scheme builder can carry
    /// per-scheme alpha (only `Surface.chromeTint` needs it).
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A scheme-reactive colour. Both values are required — N7.
    static func scheme(
        dark: UInt32,
        light: UInt32,
        darkAlpha: CGFloat = 1,
        lightAlpha: CGFloat = 1
    ) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        }
    }
}

// MARK: - §2.1 Neutral ramp

/// The four page/container fills, the one legal divider, and the floating-chrome
/// tint. Hue 72° at chroma ≤ 0.006 — charcoal, never slate, never parchment.
enum Surface {
    /// **E0.** The page. Every destination, every full-screen surface.
    static let groundUI = UIColor.scheme(dark: 0x21_1F1C, light: 0xF8_F6F5)
    /// **E1.** Grouped list containers, cards, note bubbles, fields.
    static let raisedUI = UIColor.scheme(dark: 0x2C_2A27, light: 0xFF_FEFD)
    /// **E2.** Sheets, popovers, selected rows, chip fills.
    static let elevatedUI = UIColor.scheme(dark: 0x37_3532, light: 0xFF_FFFF)
    /// Non-glass button fills, tracks, thumbnail and favicon tiles.
    static let controlUI = UIColor.scheme(dark: 0x44_423F, light: 0xED_EAE8)
    /// **S3.** The only legal 0.5pt line in the app, and only *inside* one E1
    /// container. It is not a border; it never surrounds anything.
    static let dividerUI = UIColor.scheme(dark: 0x33_312F, light: 0xE1_DFDD)
    /// **S4.** Layered over `.regularMaterial` on floating chrome and nowhere
    /// else. This is what stops body text reading through the reader's bars in
    /// light mode.
    static let chromeTintUI = UIColor.scheme(
        dark: 0x26_2421, light: 0xFB_FAF8,
        darkAlpha: 0.35, lightAlpha: 0.45
    )

    static let ground = Color(uiColor: groundUI)
    static let raised = Color(uiColor: raisedUI)
    static let elevated = Color(uiColor: elevatedUI)
    static let control = Color(uiColor: controlUI)
    static let divider = Color(uiColor: dividerUI)
    static let chromeTint = Color(uiColor: chromeTintUI)
}

/// Text and glyph values. Contrast figures in the comments are against that
/// scheme's `Surface.ground`.
enum Ink {
    /// 14.5:1 dark / 15.1:1 light. Titles, body, primary labels.
    static let primaryUI = UIColor.scheme(dark: 0xF2_F0ED, light: 0x23_201C)
    /// 7.6:1 / 6.4:1. Metadata, summaries, read-state titles. Body-safe on
    /// every surface.
    static let secondaryUI = UIColor.scheme(dark: 0xB3_B0AD, light: 0x5E_5A55)
    /// 5.8:1 / 4.8:1. On dark this drops to 4.3:1 on `elevated`, so above
    /// `ground` it is icons and ≥17pt labels only.
    static let tertiaryUI = UIColor.scheme(dark: 0x9C_9996, light: 0x71_6C67)
    /// Never text. Disabled glyphs only.
    static let quaternaryUI = UIColor.scheme(dark: 0x6B_6866, light: 0x9B_9893)

    static let primary = Color(uiColor: primaryUI)
    static let secondary = Color(uiColor: secondaryUI)
    static let tertiary = Color(uiColor: tertiaryUI)
    static let quaternary = Color(uiColor: quaternaryUI)
}

// MARK: - §2.3 The accent binding (v1 = neutral)

/// Every interactive-state colour in the app resolves here: selection,
/// activation, links, unread rails, checkmarks, prominent fills.
///
/// v1 binds all four to the neutral ramp, so the app ships with no brand hue
/// (§2.3). The binding is the *only* thing that changes when an accent
/// arrives — see A3: never shortcut through `Ink.*` on the grounds that the
/// values currently match.
enum Accent {
    /// Glyphs, text, selection marks, unread rails, active toggles, links.
    static let primaryUI = UIColor.scheme(dark: 0xF2_F0ED, light: 0x23_201C)
    /// The one prominent capsule per screen; selection chips.
    static let fillUI = UIColor.scheme(dark: 0xF2_F0ED, light: 0x23_201C)
    /// **A2.** The label/glyph on top of `fill`. Flips with the binding, so it
    /// is never written as `.white` / `.black`.
    static let onFillUI = UIColor.scheme(dark: 0x21_1F1C, light: 0xF8_F6F5)
    /// The tinted wash behind a selected row.
    static let mutedUI = UIColor.scheme(dark: 0x37_3532, light: 0xED_EAE8)

    static let primary = Color(uiColor: primaryUI)
    static let fill = Color(uiColor: fillUI)
    static let onFill = Color(uiColor: onFillUI)
    static let muted = Color(uiColor: mutedUI)
}

// MARK: - §2.2 The colour families

/// One meaning each, never decorative.
enum Semantic {
    /// Sync complete, saved.
    static let successUI = UIColor.scheme(dark: 0x51_C672, light: 0x00_7E17)
    /// Delete, remove highlight.
    static let destructiveUI = UIColor.scheme(dark: 0xFF_716B, light: 0xC2_0011)
    /// Parse failed, stale feed.
    static let warningUI = UIColor.scheme(dark: 0xE4_9900, light: 0x9E_4900)

    static let success = Color(uiColor: successUI)
    static let destructive = Color(uiColor: destructiveUI)
    static let warning = Color(uiColor: warningUI)
}

/// Row and kind identity only (§6, BR5). Never tints text, selection, controls
/// or `Accent.*`. Hues are normalised to our chip lightness so a column reads
/// as one family rather than a logo parade — Reddit is pulled to hue 58°
/// because at this lightness its brand 35° is indistinguishable from YouTube's.
enum Source {
    static let youtubeUI = UIColor.scheme(dark: 0xE8_605B, light: 0xCF_4040)
    static let redditUI = UIColor.scheme(dark: 0xDC_7200, light: 0xC4_5500)
    static let websiteUI = UIColor.scheme(dark: 0x3F_93F7, light: 0x17_79E1)

    static let youtube = Color(uiColor: youtubeUI)
    static let reddit = Color(uiColor: redditUI)
    static let website = Color(uiColor: websiteUI)
}

/// The identity chip half of the highlight family (§2.2) — swatches, picker
/// circles, the Highlights rail, the notebook rail. Saturated precisely
/// because a marker never sits behind text; the *paint* behind text stays in
/// `HighlightColor.uiColor(darkBackground:)`, which is protected work.
///
/// Wave 1 ships the values; wave 3 adopts them (`HighlightColor.marker`).
/// Markers carry `Ink.primary`'s dark value as their glyph colour, never
/// white — white-on-yellow is 1.5:1.
enum HighlightMarker {
    static let yellowUI = UIColor(rgb: 0xF9_CC21)
    static let greenUI = UIColor(rgb: 0x43_D066)
    static let blueUI = UIColor(rgb: 0x00_A5ED)
    static let pinkUI = UIColor(rgb: 0xF6_519A)

    static let yellow = Color(uiColor: yellowUI)
    static let green = Color(uiColor: greenUI)
    static let blue = Color(uiColor: blueUI)
    static let pink = Color(uiColor: pinkUI)

    /// Glyph colour for anything drawn on top of a marker.
    static let onMarkerUI = UIColor(rgb: 0x23_201C)
    static let onMarker = Color(uiColor: onMarkerUI)
}

/// Transient machine state — reading position (TTS) and search matches. No hue
/// at all, so a coloured band behind a paragraph always means the user put it
/// there. Wave 3 wires this into both readers (H5).
enum SystemState {
    static let washUI = UIColor.scheme(dark: 0x31_2F2C, light: 0xE9_E7E5)
    static let wash = Color(uiColor: washUI)
    /// Width of the `Accent.primary` leading rail that accompanies the wash.
    static let railWidth: CGFloat = 3

    /// The luminance step the wash makes from the page it sits on: **darker**
    /// on a light page, **lighter** on a dark one, equal on every channel so no
    /// hue is introduced (§2.2, "a luminance wash only").
    ///
    /// 16/255 is read straight off the token pair — `Surface.ground` `#211F1C`
    /// → `#312F2C` is exactly +16 on all three channels, and `#F8F6F5` →
    /// `#E9E7E5` is −15/−15/−16.
    static let washStep: CGFloat = 16.0 / 255.0

    /// The wash over an arbitrary reader page.
    ///
    /// §2.2 specifies the wash against `Surface.ground`, but the reader has
    /// eight hand-tuned papers (T1/T2) and the wash has to work on all of them;
    /// a fixed `#E9E7E5` band over sepia would be exactly the "coloured band"
    /// the section forbids. So the *step* is the token and the paper is the
    /// base: over `Surface.ground` this reproduces `SystemState.wash` to within
    /// 1/255, and over every other paper it stays hueless.
    ///
    /// `darkBackground` is the reader theme's own darkness, not the UI scheme —
    /// a light-mode app can be showing a dark paper.
    static func washUI(overPaper paper: UIColor, darkBackground: Bool) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        guard paper.getRed(&r, green: &g, blue: &b, alpha: &a) else { return paper }
        let step = darkBackground ? washStep : -washStep
        func shift(_ c: CGFloat) -> CGFloat { min(1, max(0, c + step)) }
        return UIColor(red: shift(r), green: shift(g), blue: shift(b), alpha: 1)
    }

    /// The wash's companion rail, resolved for the reader page's darkness
    /// rather than the UI scheme. **A1** — it is `Accent.primary`, never
    /// `Ink.primary`, because it marks machine state on the page.
    static func railUI(darkBackground: Bool) -> UIColor {
        Accent.primaryUI.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: darkBackground ? .dark : .light)
        )
    }
}

// MARK: - §7.1 Control tiers

/// Three tiers, and no more (Z2). A control that "needs" a 32 or 38pt tier is
/// a Standard control with different padding.
enum ControlTier {
    /// Inline chips, tags, swatches, favicon tiles, monograms. Tap target is
    /// padded to `hitTarget` if interactive (Z1) — the art does not grow.
    case small
    /// Every ordinary tappable control: glass circles, toolbar items, row
    /// accessories, list rows. The hit-area floor.
    case standard
    /// The one primary capsule per screen.
    case prominent

    var height: CGFloat {
        switch self {
        case .small: return 28
        case .standard: return 44
        case .prominent: return 52
        }
    }

    /// Optical size of the glyph inside the control.
    var glyph: CGFloat {
        switch self {
        case .small: return 14
        case .standard: return 17
        case .prominent: return 20
        }
    }

    /// **Z1.** Minimum hit target for anything tappable, whatever its art size.
    static let hitTarget: CGFloat = 44
}

// MARK: - §7.2 Radii and padding

/// Continuous corners everywhere (Z4). Never `.circular`.
enum Radius {
    /// E1 container.
    static let container: CGFloat = 16
    /// E3 floating panel.
    static let floatingPanel: CGFloat = 22
    static let thumbnail: CGFloat = 8
    static let faviconTile: CGFloat = 6

    /// **Z3, nested radius rule.** An inner radius is the outer radius minus
    /// the padding between them; a 16pt container with 16pt padding holds
    /// 8pt children, never another 16pt.
    static func nested(in outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(0, outer - padding)
    }
}

enum Metric {
    /// Screen horizontal margin.
    static let screenMargin: CGFloat = 20
    /// Inner padding of an E1 container and an E3 floating panel.
    static let containerPadding: CGFloat = 16
    /// The gap between E1 containers. This gap *is* the separator (S2).
    static let containerGap: CGFloat = 16
    /// Pills, capsules, chips.
    static let capsuleHorizontalPadding: CGFloat = 16
    static let capsuleVerticalPadding: CGFloat = 10
    /// List row vertical padding.
    static let rowVerticalPadding: CGFloat = 12
    /// Thumbnail slot (R4). Reserved even when empty so rhythm stays even.
    static let thumbnailSize = CGSize(width: 96, height: 54)
    /// Favicon tile (BR1): a 20pt mark centred on a 28pt tile.
    static let faviconTile: CGFloat = 28
    static let faviconMark: CGFloat = 20
    /// **§8.2.** The detent for a **Form** sheet — Add link, Add feed. One
    /// field never gets a full screen, and both of the app's form sheets get
    /// the same height so they read as one component in two dresses.
    static let formSheetHeight: CGFloat = 220
}

// MARK: - §3 Elevations, as view modifiers

extension View {
    /// **E1.** A grouped container: `Surface.raised`, 16pt continuous corner,
    /// no stroke (S2). Light mode gets the one legal shadow; dark gets none,
    /// because the value step already reads.
    func elevationContainer(cornerRadius: CGFloat = Radius.container) -> some View {
        modifier(ElevationContainer(cornerRadius: cornerRadius))
    }

    /// **E3.** Floating glass chrome over scrolling content: `.regularMaterial`
    /// plus the `Surface.chromeTint` overlay, in **both** schemes (S4).
    /// `.ultraThinMaterial` / `.thinMaterial` are banned over the reader.
    func floatingChrome(in shape: some Shape) -> some View {
        background {
            shape
                .fill(.regularMaterial)
                .overlay { shape.fill(Surface.chromeTint) }
        }
        .compositingGroup()
        .modifier(FloatingChromeShadow())
    }
}

private struct ElevationContainer: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Surface.raised, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0 : 0.05),
                radius: 8 / 2, // SwiftUI radius is ~half a CSS blur
                y: 2
            )
    }
}

private struct FloatingChromeShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(colorScheme == .dark ? 0.18 : 0.10),
            radius: 16 / 2,
            y: 4
        )
    }
}

// MARK: - §3 S5/S6 — chrome reserves its own space

/// Content insets the reader owes its floating chrome.
///
/// **S5** every floating chrome element publishes `its height + 12pt` as an
/// inset on the scroll view, so content never passes under chrome at rest.
/// **S6** the inset is reserved whether chrome is shown or hidden, so
/// revealing chrome never moves text.
///
/// Both readers consume these — the plain TextKit reader
/// (`HighlightableTextView`) and the block reader (`BlockReaderView`). A value
/// changed here must land in both, which is why it lives in one place.
enum ReaderChrome {
    /// Gap between chrome and the nearest line of text (S5).
    static let clearance: CGFloat = 12
    /// The floating action bar's own height (§7.3 target).
    static let actionBarHeight = ControlTier.standard.height
    /// How far the action bar floats above the safe area (§7.3).
    static let actionBarBottomOffset: CGFloat = 16

    /// Bottom content inset, measured from the safe-area edge. Reserved
    /// unconditionally: the audio capsule is at-rest chrome during read-aloud,
    /// and S6 forbids the text moving when the idle bar comes and goes.
    static let bottomReserve = actionBarBottomOffset + actionBarHeight + clearance

    /// Top reading padding above the frozen safe-area inset.
    static let topReading: CGFloat = 24

    /// The frozen top inset shared by both readers.
    ///
    /// Freezes at the smallest positive safe-area top ever seen — the
    /// immersive, chrome-hidden value — so revealing the nav bar cannot push
    /// the article down (S6). A transient `0` (mid-transition, detached view)
    /// never unfreezes or shrinks it. Revealed chrome overlays the text
    /// instead of displacing it, which is why S4's material floor is not
    /// optional.
    static func frozenTop(live: CGFloat, frozen: CGFloat?) -> CGFloat? {
        guard live > 0 else { return frozen }
        return min(frozen ?? live, live)
    }

    /// The *device* safe area — notch/status bar and home indicator — read
    /// from the key window.
    ///
    /// This is deliberately not the SwiftUI container safe area. A bar shown
    /// by `.toolbar` inflates the view controller's safe area but never the
    /// window's, so this value is constant across a chrome reveal. That is
    /// exactly the S6 contract: a reader that pads by this number reserves the
    /// same space whether chrome is up or down. `ReaderTextView` gets the same
    /// figure from UIKit's own `safeAreaInsets`; the block reader has no
    /// UIKit view to ask, so it asks here.
    @MainActor
    static var deviceSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}
