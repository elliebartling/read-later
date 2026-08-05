import SwiftUI
import SwiftData

// The reader's typography sheet — a **plain grouped list**, and deliberately so.
//
// Wave 5 rebuilt this as a bento grid of mixed-size self-illustrating tiles.
// Ellen struck it: *"the bento box concept is not landing, and just makes the
// text size (the one thing people are most likely to change?) most difficult to
// manage by making its scale smaller."* A spatial panel spends its biggest
// tiles on the choices people make once (theme, face) and squeezes the one they
// make constantly into a half-width cell. So:
//
//  - **Text size leads, at full width.** It is the first section, it renders a
//    live specimen in the chosen face at the chosen size, and its slider gets
//    the entire measure. Nothing above it, nothing beside it.
//  - **One list, one grammar.** Grouped `Form` sections, same as every other
//    settings surface in the app (§8.1). No grid.
//  - **B2 survives the revert.** One slider treatment — bare track, value
//    trailing the control, never on a row of its own. The sheet used to have
//    two different sliders and three places to read a number.
//  - **B3 survives the revert.** Read aloud is not here; it lives in Settings.
//    The sheet was the app's second copy of that picker.
//  - **§10 M1.** Nothing here animates the article: font, size and spacing
//    changes apply instantly. Only the sheet's own selection marks move.

struct TypographyControls: View {
    @Bindable var settings: AppSettings
    /// Optional live controller, retained so a future control that affects
    /// playback can reach it. Read aloud itself lives in Settings (B3).
    var controller: TTSController? = nil
    @Environment(\.dismiss) private var dismiss

    private let swatchColumns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                // The one control people reach for, first and full width.
                Section("Text size") {
                    sizeSpecimen
                    sliderRow(
                        value: $settings.readerFontSize, range: 12...32,
                        unit: "pt", accessibilityName: "Text size"
                    )
                }

                Section("Theme") {
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
                        paletteLabel("Light theme")
                        swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
                        paletteLabel("Dark theme")
                        swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
                    }
                }

                Section("Font") {
                    ForEach(ReaderFont.Group.allCases) { group in
                        let fonts = ReaderFont.allCases.filter { $0.group == group }
                        if !fonts.isEmpty {
                            paletteLabel(group.title)
                            ForEach(fonts) { font in
                                FontRow(
                                    font: font,
                                    selected: settings.readerFontRaw == font.rawValue
                                ) { settings.readerFontRaw = font.rawValue }
                            }
                        }
                    }
                }

                // B2 — one slider treatment, so the two spacings share a
                // section instead of owning a header each.
                Section("Spacing") {
                    sliderRow(
                        value: $settings.readerLineSpacing, range: 0...16,
                        label: "Line", unit: "pt"
                    )
                    sliderRow(
                        value: $settings.readerParagraphSpacing, range: 0...28,
                        label: "Paragraph", unit: "pt"
                    )
                }

                Section("Width") {
                    Picker("Width", selection: widthBinding) {
                        ForEach(ReaderWidth.allCases) { w in
                            Text(w.displayName).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .pageForm()
            .navigationTitle("Typography")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // §8.2 — an Editor sheet: changes commit live, so `Done` only.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The article stays visible while it is being tuned.
        .presentationDetents([.medium, .large])
    }

    // MARK: - Size

    /// The specimen answers "what does this number mean?" without the number
    /// having to be read — the chosen face at the chosen size, full measure.
    private var sizeSpecimen: some View {
        Text("The quick brown fox")
            .font(Font(currentFont.uiFont(size: CGFloat(settings.readerFontSize))))
            .foregroundStyle(Ink.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    /// **B2**, as one component. The sheet previously had two slider treatments
    /// and put every value on a row of its own.
    private func sliderRow(
        value: Binding<Double>, range: ClosedRange<Double>,
        label: String? = nil, unit: String, accessibilityName: String? = nil
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

    private func paletteLabel(_ title: String) -> some View {
        Text(title)
            // §4.3 section header: sentence case, never all-caps (T7).
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.secondary)
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
        .padding(.vertical, 4)
    }
}

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

/// A tappable paper swatch showing a theme's background + a sample glyph in its
/// ink color.
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
                // No ring (S2). Selection is the one SH2 mark.
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

/// A font-family row rendered in its own typeface, with the SH2 mark when active.
private struct FontRow: View {
    let font: ReaderFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(font.displayName)
                    .font(Font(font.uiFont(size: 18)))
                    .foregroundStyle(Ink.primary)
                Spacer(minLength: 8)
                if selected { SelectionCheck() }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
