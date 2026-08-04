import SwiftUI
import SwiftData

// §8.6 — the bento grid. **Reserved for exactly one surface**, and this is it.
//
// What it replaced: a `Form` of six grouped sections ("Theme", "Font", "Size",
// "Line Spacing", "Paragraph Spacing", "Width", plus a duplicated "Read Aloud"),
// six headers, and two different slider treatments — one with A/A end labels
// and one bare, each with its value on its own row underneath. Tuning how an
// article reads meant scrolling a settings screen while the article was
// nowhere in sight.
//
//  - **§8.6** mixed-size tiles on `Surface.raised`, each a **live
//    self-illustrating preview**: the theme tiles render real ink on real
//    paper, the font tiles render their own faces, the size tile renders the
//    chosen face at the chosen size, and the width tiles draw the measure they
//    set. It is the only place in the app where a grid replaces a list.
//  - **B1.** No paper-swatch fans, no page curls, no textures (N4). The
//    preview *is* the decoration.
//  - **B2.** Numeric values sit **trailing the control**, never on their own
//    row. One slider treatment: bare track, trailing value.
//  - **B3.** `.medium` so the article stays visible while being tuned, and
//    **Read aloud is gone from here** — it lives in Settings only.
//  - **S2/Z3/Z4.** Tiles are fills, never strokes; nested radii derive from the
//    tile's 16pt corner minus its 16pt padding; corners are continuous.
//  - **§10 M1.** Nothing here animates the article: font, size and spacing
//    changes apply instantly. Only the panel's own selection marks move.

struct TypographyControls: View {
    @Bindable var settings: AppSettings
    /// Optional live controller, retained so a future control that affects
    /// playback can reach it. Read aloud itself moved to Settings (B3).
    var controller: TTSController? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metric.containerGap) {
                    themeTile
                    fontTile
                    HStack(alignment: .top, spacing: Metric.containerGap) {
                        sizeTile
                        widthTile
                    }
                    spacingTile
                }
                .padding(.horizontal, Metric.screenMargin)
                .padding(.vertical, Metric.containerGap)
            }
            .pageBackground()
            .navigationTitle("Typography")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // §8.2 — an Editor sheet: changes commit live, so `Done` only.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // B3 — the article stays visible while it is being tuned.
        .presentationDetents([.medium, .large])
    }

    // MARK: - Theme

    private var themeTile: some View {
        BentoTile(title: "Theme") {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(ReaderAppearance.allCases) { a in
                    Text(a.displayName).tag(a)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch settings.readerAppearance {
            case .light:
                swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
            case .dark:
                swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
            case .system:
                tileCaption("Light")
                swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
                tileCaption("Dark")
                swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
            }
        }
    }

    private func swatchGrid(_ themes: [ReaderTheme], selection: Binding<ReaderTheme>) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 68), spacing: 10)],
            spacing: 10
        ) {
            ForEach(themes) { theme in
                ThemeTile(theme: theme, selected: selection.wrappedValue == theme) {
                    selection.wrappedValue = theme
                }
            }
        }
    }

    // MARK: - Font

    private var fontTile: some View {
        BentoTile(title: "Font") {
            ForEach(ReaderFont.Group.allCases) { group in
                let fonts = ReaderFont.allCases.filter { $0.group == group }
                if !fonts.isEmpty {
                    tileCaption(group.title)
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10),
                                  GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(fonts) { font in
                            FontTile(
                                font: font,
                                selected: settings.readerFontRaw == font.rawValue
                            ) { settings.readerFontRaw = font.rawValue }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Size

    /// The size tile illustrates itself: the specimen is the chosen face at the
    /// chosen size, so the number never has to be read to know what it does.
    private var sizeTile: some View {
        BentoTile(title: "Size") {
            Text("Aa")
                .font(Font(currentFont.uiFont(size: CGFloat(settings.readerFontSize))))
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .lineLimit(1)
                .accessibilityHidden(true)
            // B2 — bare track, value trailing the control. No leading label:
            // the tile is already titled "Size", and a half-width tile has no
            // room to say it twice.
            sliderRow(
                value: $settings.readerFontSize, range: 12...32,
                label: nil, unit: "pt", accessibilityName: "Size"
            )
        }
    }

    // MARK: - Width

    /// Each width option draws the measure it sets — four little columns of
    /// text rules at four insets.
    private var widthTile: some View {
        BentoTile(title: "Width") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10),
                          GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(ReaderWidth.allCases) { width in
                    WidthTile(width: width, selected: settings.readerWidth == width) {
                        settings.readerWidth = width
                    }
                }
            }
        }
    }

    // MARK: - Spacing

    private var spacingTile: some View {
        BentoTile(title: "Spacing") {
            sliderRow(
                value: $settings.readerLineSpacing, range: 0...16,
                label: "Line", unit: "pt"
            )
            sliderRow(
                value: $settings.readerParagraphSpacing, range: 0...28,
                label: "Paragraph", unit: "pt"
            )
        }
    }

    /// **B2**, as one component. The app previously had two slider treatments
    /// and put every value on a row of its own.
    private func sliderRow(
        value: Binding<Double>, range: ClosedRange<Double>,
        label: String?, unit: String, accessibilityName: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            if let label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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

    private func tileCaption(_ text: String) -> some View {
        Text(text)
            // §4.3 section header: sentence case, never all-caps (T7).
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
}

// MARK: - Tile chrome

/// One bento tile: an **E1** container — `Surface.raised`, 16pt continuous
/// corner, 16pt inner padding, no stroke (S2).
private struct BentoTile<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                // §4.3 — section header tier.
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.containerPadding)
        .elevationContainer()
    }
}

/// **Z3.** Children of a 16pt tile with 16pt padding carry an 8pt radius.
private let bentoChildRadius = Radius.nested(
    in: Radius.container, padding: Metric.containerPadding
)

/// **SH2.** The one selection idiom: a filled `Accent.fill` circle with an
/// `Accent.onFill` checkmark. Never a ring (S2), never a tinted label.
private struct SelectionCheck: View {
    var body: some View {
        Image(systemName: "checkmark")
            .uiGlyph(size: 11)
            .foregroundStyle(Accent.onFill)
            .frame(width: 18, height: 18)
            .background(Accent.fill, in: .circle)
    }
}

/// A paper tile: the theme's real ink on its real paper (B1 — the preview is
/// the decoration; there is no texture, no curl, no swatch fan).
private struct ThemeTile: View {
    let theme: ReaderTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: bentoChildRadius, style: .continuous)
                        .fill(Color(uiColor: theme.background))
                    Text("Aa")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: theme.foreground))
                }
                .frame(height: 46)
                .overlay(alignment: .topTrailing) {
                    if selected { SelectionCheck().padding(5) }
                }
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A face tile, rendered in its own face — the specimen and the control are
/// the same object.
private struct FontTile: View {
    let font: ReaderFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aa")
                        .font(Font(font.uiFont(size: 20)))
                        .foregroundStyle(Ink.primary)
                    Text(font.displayName)
                        .font(Font(font.uiFont(size: 12)))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if selected { SelectionCheck() }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: ControlTier.hitTarget + 8, alignment: .leading)
            // A1 — selection is `Accent.muted`. The unselected well is
            // `Surface.ground`, NOT `Surface.control`: in light mode the
            // control fill and `Accent.muted` are the same value, so a
            // selected tile was indistinguishable from an idle one.
            .background(
                selected ? Accent.muted : Surface.ground,
                in: .rect(cornerRadius: bentoChildRadius, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A measure tile: three text rules drawn at the inset the option sets, so the
/// control shows the column it produces.
private struct WidthTile: View {
    let width: ReaderWidth
    let selected: Bool
    let action: () -> Void

    /// The widest inset in the set, used to normalise the previews so the four
    /// tiles read as one scale rather than four unrelated drawings.
    private var insetFraction: CGFloat {
        width.horizontalInset / 96
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                GeometryReader { geo in
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(selected ? Accent.primary.opacity(0.7) : Ink.quaternary)
                                .frame(height: 2)
                                .padding(.horizontal, geo.size.width * insetFraction * 0.5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 22)
                Text(width.displayName)
                    .font(.caption2)
                    .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Accent.muted : Surface.ground,
                in: .rect(cornerRadius: bentoChildRadius, style: .continuous)
            )
            // SH2 — one selection idiom app-wide, including here.
            .overlay(alignment: .topTrailing) {
                if selected { SelectionCheck().padding(4) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(width.displayName) width")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
