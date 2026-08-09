import AVFoundation
import SwiftData
import SwiftUI

// The reader's appearance sheet — **three tabs, and no lines**.
//
// Ellen, on build 44: *"UX of the typography sheet: I feel like we need to
// break this into tabs—color, type, audio. I'd love to try type options as
// 'blocks' as well as the colors. The theme picker itself has too many
// borders/lines. I thought we had a specific design guidance *against*
// borders? And yet they're EVERYWHERE."*
//
// She is right on the last point, and the diagnosis is worth writing down
// because the offending lines were never authored by hand. The old sheet was a
// grouped `Form`, so **every line came free with the container**: five section
// cards, each reading as an outline against the sheet (N2/S2), plus a 0.5pt
// hairline between every pair of rows inside them — nineteen of those, thirteen
// in the font list alone. S3 permits row separators *inside* one E1 container,
// which is how a `Form` slipped past the border ban one row at a time. The fix
// is not to disable separators on a `Form`; it is to stop using one. This sheet
// is a plain `VStack` on the page ground, and whitespace does all of the
// separating. **24 lines removed, 0 added.**
//
// What the rebuild keeps from the list version (§8.6, all still governing):
//
//  - **B0. Text size leads, at full width.** It is the first thing in the first
//    tab you land on, it renders a live specimen in the chosen face at the
//    chosen size, and its slider gets the whole measure. *Prominence follows
//    frequency* is also why the sheet opens on **Type** rather than on the
//    leftmost tab: the control people touch constantly is one glance away, not
//    one tap. The tab *order* is Ellen's (colour, type, audio); only the
//    landing tab is chosen by frequency.
//  - **B1.** No paper fans, no textures. The live specimens are the decoration.
//  - **B2.** One slider treatment: bare track, value trailing the control,
//    never on a row of its own.
//  - **§10 M1.** Nothing here animates the article. Font, size and spacing
//    apply instantly; only the sheet's own selection marks move.
//
// What changed, and why:
//
//  - **B3 is amended, not struck** (see `docs/design-language.md` §8.6). Read
//    aloud was removed from this sheet in wave 5 because it was a *duplicate*
//    of the Settings picker. The Audio tab is not that duplicate: it carries
//    the two controls that belong to the reading session in front of you —
//    **speed and voice**, both of which apply live to a running playback — and
//    it leaves the account-level configuration (**provider** and the OpenAI
//    **API key**) in Settings, where it is set once. The split is stated in the
//    tab's own footnote so nobody has to guess which screen owns what.
//  - **Typefaces are blocks, exactly like the theme swatches** — same tile,
//    same grid, same SH2 mark in the same corner, "Aa" set in the face with the
//    name captioned underneath. Setting the *name* in its own face instead was
//    tried first and is the better specimen on paper; it was reverted because
//    the selection mark owns the tile's top-trailing corner and a centred word
//    of any length runs straight through it. The swatch shape keeps that corner
//    empty by construction, which is exactly why it captions outside the tile.
//  - **The three group headers over the font list are gone** (Reading /
//    Accessibility / Sans). In a list of names they told you what kind of face
//    you were looking at; over a grid of specimens the specimen already says
//    it, which makes them three more lines answering no question (N3). The
//    order is unchanged, so the groups still read as groups.

struct ReaderAppearanceSheet: View {
    @Bindable var settings: AppSettings
    /// The live playback controller. The Audio tab needs it: speed and voice
    /// changes apply to a playing article immediately rather than at next play.
    var controller: TTSController?
    @Environment(\.dismiss) private var dismiss

    /// **B0.** Lands on Type, because text size is the control people reach for.
    /// Named rather than inlined so a test can assert it is not the leftmost
    /// tab — the day it becomes `.color`, text size has quietly stopped
    /// leading the sheet.
    static let landingTab: Tab = .type

    @State private var tab: Tab = ReaderAppearanceSheet.landingTab
    /// Filled once on appear — `AVSpeechSynthesisVoice.speechVoices()` walks the
    /// installed voice catalogue and has no business running on every body pass.
    @State private var appleVoices: [AVSpeechSynthesisVoice] = []

    /// Ellen's three, in her order. The landing tab is chosen separately (B0).
    enum Tab: String, CaseIterable, Identifiable {
        case color = "Color"
        case type = "Type"
        case audio = "Audio"
        var id: String { rawValue }
    }

    private let swatchColumns = [GridItem(.adaptive(minimum: 72), spacing: 10)]
    private let faceColumns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    /// Section-to-section breathing room. This gap is the separator (S2) — it
    /// is doing the job the five `Form` section cards used to do.
    private let sectionGap: CGFloat = 14

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                tabPicker
                // `.basedOnSize` so the short tabs sit still and only the tall
                // one scrolls — and it only has to at large Dynamic Type,
                // which is the case the single detent cannot cover (T9).
                ScrollView {
                    VStack(alignment: .leading, spacing: sectionGap) {
                        switch tab {
                        case .color: colorTab
                        case .type: typeTab
                        case .audio: audioTab
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metric.screenMargin)
                    .padding(.bottom, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.top, 4)
            .pageBackground()
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // §8.2 — an Editor sheet: changes commit live, so `Done` only.
                // SH1: the sheet always has a visible way out.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // One detent, sized so the tallest tab fits without scrolling at the
        // default text size, and the article still shows above it.
        .presentationDetents([.fraction(0.79)])
        .task {
            if appleVoices.isEmpty { appleVoices = VoiceCatalog.appleVoices() }
        }
    }

    // MARK: - The switcher

    private var tabPicker: some View {
        Picker("Appearance section", selection: $tab) {
            ForEach(Tab.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Metric.screenMargin)
    }

    // MARK: - Color

    /// No "Theme" header: the tab is the header. In system mode the two
    /// palettes are told apart by a label and a gap, not by a rule between them.
    @ViewBuilder
    private var colorTab: some View {
        Picker("Appearance", selection: appearanceBinding) {
            ForEach(ReaderAppearance.allCases) { a in
                Text(a.displayName).tag(a)
            }
        }
        .pickerStyle(.segmented)

        switch settings.readerAppearance {
        case .light:
            swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
        case .dark:
            swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
        case .system:
            section("Light theme") {
                swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
            }
            section("Dark theme") {
                swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
            }
        }
    }

    private func swatchGrid(_ themes: [ReaderTheme], selection: Binding<ReaderTheme>) -> some View {
        LazyVGrid(columns: swatchColumns, spacing: 12) {
            ForEach(themes) { theme in
                ThemeSwatch(
                    theme: theme,
                    selected: selection.wrappedValue == theme
                ) { selection.wrappedValue = theme }
            }
        }
    }

    // MARK: - Type

    @ViewBuilder
    private var typeTab: some View {
        // **B0.** First, full measure, nothing beside it.
        section("Text size") {
            sizeSpecimen
            sliderRow(
                value: $settings.readerFontSize, range: 12 ... 32,
                unit: "pt", accessibilityName: "Text size"
            )
        }

        section("Typeface") {
            LazyVGrid(columns: faceColumns, spacing: 8) {
                ForEach(ReaderFont.allCases) { font in
                    FaceSpecimen(
                        font: font,
                        selected: settings.readerFontRaw == font.rawValue
                    ) { settings.readerFontRaw = font.rawValue }
                }
            }
        }

        // Line, paragraph and margin are one question — how much air does the
        // page get — so they are one group with one grammar: label, control,
        // value (B2). Margins is a segmented control rather than a slider
        // because `ReaderWidth` has four named stops, not a continuum.
        section("Spacing") {
            sliderRow(
                value: $settings.readerLineSpacing, range: 0 ... 16,
                label: "Line", unit: "pt"
            )
            sliderRow(
                value: $settings.readerParagraphSpacing, range: 0 ... 28,
                label: "Paragraph", unit: "pt"
            )
            HStack(spacing: 12) {
                controlLabel("Margins")
                Picker("Margins", selection: widthBinding) {
                    ForEach(ReaderWidth.allCases) { w in
                        Text(w.displayName).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    /// The specimen answers "what does this number mean?" without the number
    /// having to be read — the chosen face at the chosen size, full measure.
    /// The frame is fixed so dragging the slider never reflows the sheet (M1).
    private var sizeSpecimen: some View {
        Text("The quick brown fox")
            .font(Font(currentFont.uiFont(size: CGFloat(settings.readerFontSize))))
            .foregroundStyle(Ink.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .accessibilityHidden(true)
    }

    // MARK: - Audio

    /// **B3, amended.** Session controls here; account configuration in
    /// Settings. Speed leads for the same reason text size does — it is the one
    /// you change mid-article.
    @ViewBuilder
    private var audioTab: some View {
        section("Speed") {
            Picker("Speed", selection: rateBinding) {
                ForEach(Self.speedSteps, id: \.self) { r in
                    Text(AudioPlayerBar.speedLabel(for: r)).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        section("Voice") {
            // A `Picker` in `.menu` style carries the system button's own
            // content insets, which push its label ~10pt off the sheet's text
            // column — a small misalignment, but the whole point of this
            // rebuild is that the eye has nothing but alignment to go on. So
            // the menu wears our own label and sits flush with everything else.
            Menu {
                Picker("Voice", selection: voiceBinding) {
                    switch settings.ttsProvider {
                    case .apple:
                        Text("System default").tag("")
                        ForEach(appleVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    case .openAI:
                        ForEach(VoiceCatalog.openAIVoices, id: \.self) { v in
                            Text(v.capitalized).tag(v)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentVoiceLabel)
                        .lineLimit(1)
                    // The set's own caret, turned to point at the menu it
                    // opens. Still one icon set (I11) — no second-set glyph.
                    Image(.caretRight)
                        .uiGlyph(size: 11)
                        .rotationEffect(.degrees(90))
                }
                // A1 — an interactive colour is never `Ink.*`.
                .foregroundStyle(Accent.primary)
                .contentShape(.rect)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            .accessibilityLabel("Voice")
            .accessibilityValue(currentVoiceLabel)

            // SH4 — an explanatory subtitle is never tinted. This is also the
            // written form of the B3 split, so the sheet says which screen owns
            // what instead of leaving the user to hunt.
            Text("Speed and voice apply while you listen. The provider — \(settings.ttsProvider.displayName) — and its API key are set in Settings.")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The steps the player capsule cycles through, so the two controls cannot
    /// offer different speeds. A test pins them equal.
    static let speedSteps: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    /// What the closed menu says. Apple's identifiers are opaque, so this goes
    /// through the same catalogue the player capsule uses.
    private var currentVoiceLabel: String {
        let raw = voiceBinding.wrappedValue
        if settings.ttsProvider == .apple, raw.isEmpty { return "System default" }
        return VoiceCatalog.displayName(provider: settings.ttsProvider, voice: raw)
    }

    // MARK: - Shared pieces

    /// A section: a §4.3 header, then its controls, with a gap where the old
    /// `Form` put a card edge.
    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            content()
        }
    }

    /// §4.3 section header: `.subheadline` semibold, `Ink.secondary`, sentence
    /// case (T7).
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.secondary)
    }

    /// The leading label of a control row — the one grammar every row in the
    /// Spacing group shares.
    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Ink.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// **B2**, as one component: bare track, value trailing the control.
    private func sliderRow(
        value: Binding<Double>, range: ClosedRange<Double>,
        label: String? = nil, unit: String, accessibilityName: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            if let label {
                controlLabel(label)
            }
            Slider(value: value, in: range, step: 1)
                .tint(Accent.primary)
                .labelsHidden()
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Ink.tertiary)
                // T8 — a value is arbitrary content; it never wraps.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityName ?? label ?? "")
    }

    // MARK: - Bindings

    private var currentFont: ReaderFont {
        ReaderFont(rawValue: settings.readerFontRaw) ?? .serif
    }

    private var appearanceBinding: Binding<ReaderAppearance> {
        Binding(
            get: { settings.readerAppearance },
            set: { settings.readerAppearance = $0 }
        )
    }

    private var widthBinding: Binding<ReaderWidth> {
        Binding(
            get: { settings.readerWidth },
            set: { settings.readerWidth = $0 }
        )
    }

    private var lightThemeBinding: Binding<ReaderTheme> {
        Binding(
            get: { settings.readerLightTheme },
            set: { settings.readerLightTheme = $0 }
        )
    }

    private var darkThemeBinding: Binding<ReaderTheme> {
        Binding(
            get: { settings.readerDarkTheme },
            set: { settings.readerDarkTheme = $0 }
        )
    }

    /// Persisted **and** applied live — the article is playing behind the sheet,
    /// so a speed change that only took effect next time would read as broken.
    private var rateBinding: Binding<Double> {
        Binding(
            get: { ReaderAppearanceSheet.nearestSpeedStep(to: settings.ttsRate) },
            set: {
                settings.ttsRate = $0
                controller?.setRate($0)
            }
        )
    }

    /// Reads and writes whichever voice field the active provider owns, so the
    /// sheet never has to know it is looking at two stored properties.
    private var voiceBinding: Binding<String> {
        Binding(
            get: { settings.ttsProvider == .apple ? settings.appleVoiceID : settings.openAIVoice },
            set: { newValue in
                if settings.ttsProvider == .apple {
                    settings.appleVoiceID = newValue
                } else {
                    settings.openAIVoice = newValue
                }
                controller?.setVoice(newValue)
            }
        )
    }

    /// A segmented picker can only select a tag it renders. A stored rate that
    /// is not one of the five steps (an older build cycled different values)
    /// would otherwise show no selection at all, so it snaps to the nearest.
    static func nearestSpeedStep(to rate: Double) -> Double {
        speedSteps.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 1.0
    }
}

/// **SH2.** The one selection idiom: a filled `Accent.fill` circle with an
/// `Accent.onFill` checkmark. Never a ring (S2), never a tinted label — and
/// never a second treatment for the second grid, which is why both the theme
/// swatches and the face specimens below use this exact view.
private struct SelectionCheck: View {
    var body: some View {
        Image(.check)
            .uiGlyph(size: 11)
            .foregroundStyle(Accent.onFill)
            .frame(width: 18, height: 18)
            .background(Accent.fill, in: .circle)
    }
}

/// A tappable paper swatch showing a theme's background + a sample glyph in its
/// ink colour. No stroke, no ring: the fill is the swatch (S2).
private struct ThemeSwatch: View {
    let theme: ReaderTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: theme.background))
                    Text("Aa")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: theme.foreground))
                }
                .frame(height: 48)
                .overlay(alignment: .topTrailing) {
                    if selected { SelectionCheck().padding(5) }
                }
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A typeface, as a block — **the theme swatch's twin**. Same tile, same grid,
/// same SH2 mark in the same corner; only the tile's content differs, because a
/// theme has a paper to show and a face has an "Aa" to set.
///
/// The tile is a *fill*, not an outline — same as a favicon tile (BR1). Nothing
/// here is stroked.
///
/// The name lives in a caption *under* the tile rather than inside it. Setting
/// the name in its own face reads better on paper, but the selection mark then
/// lands on top of the word: the mark occupies the tile's top-trailing corner,
/// and a centred word of any length runs straight through it. The swatch shape
/// keeps that corner empty by construction, which is the whole reason it puts
/// its label outside.
private struct FaceSpecimen: View {
    let font: ReaderFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Surface.control)
                    Text("Aa")
                        .font(Font(font.uiFont(size: 20)))
                        .foregroundStyle(Ink.primary)
                }
                .frame(height: 44)
                .overlay(alignment: .topTrailing) {
                    if selected { SelectionCheck().padding(5) }
                }
                Text(font.displayName)
                    .font(.caption2)
                    .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
