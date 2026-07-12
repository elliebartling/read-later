import SwiftUI
import SwiftData

struct TypographyControls: View {
    @Bindable var settings: AppSettings
    /// Optional live controller so a voice change while listening applies
    /// immediately (restarts the current paragraph) rather than next start.
    var controller: TTSController? = nil
    @Environment(\.dismiss) private var dismiss

    private let swatchColumns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    LazyVGrid(columns: swatchColumns, spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            ThemeSwatch(
                                theme: theme,
                                selected: settings.readerTheme == theme
                            ) { settings.readerTheme = theme }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Font") {
                    ForEach(ReaderFont.Group.allCases) { group in
                        let fonts = ReaderFont.allCases.filter { $0.group == group }
                        if !fonts.isEmpty {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(fonts) { font in
                                FontRow(
                                    font: font,
                                    selected: settings.readerFontRaw == font.rawValue
                                ) { settings.readerFontRaw = font.rawValue }
                            }
                        }
                    }
                }

                Section("Size") {
                    Slider(value: $settings.readerFontSize, in: 12...32, step: 1) {
                        Text("Size")
                    } minimumValueLabel: {
                        Text("A").font(.footnote)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    Text("\(Int(settings.readerFontSize)) pt")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Line Spacing") {
                    Slider(value: $settings.readerLineSpacing, in: 0...16, step: 1)
                    Text("\(Int(settings.readerLineSpacing)) pt")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Paragraph Spacing") {
                    Slider(value: $settings.readerParagraphSpacing, in: 0...28, step: 1)
                    Text("\(Int(settings.readerParagraphSpacing)) pt")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Width") {
                    Picker("Width", selection: .init(
                        get: { settings.readerWidth },
                        set: { settings.readerWidth = $0 }
                    )) {
                        ForEach(ReaderWidth.allCases) { w in
                            Text(w.displayName).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Read Aloud") {
                    Picker("Provider", selection: $settings.ttsProvider) {
                        ForEach(TTSProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    switch settings.ttsProvider {
                    case .apple:
                        Picker("Voice", selection: appleVoiceBinding) {
                            Text("System Default").tag("")
                            ForEach(VoiceCatalog.appleVoices(), id: \.identifier) { voice in
                                Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                            }
                        }
                    case .openAI:
                        Picker("Voice", selection: openAIVoiceBinding) {
                            ForEach(VoiceCatalog.openAIVoices, id: \.self) { v in
                                Text(v.capitalized).tag(v)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Typography")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var openAIVoiceBinding: Binding<String> {
        Binding(
            get: { settings.openAIVoice },
            set: { newVoice in
                settings.openAIVoice = newVoice
                controller?.setVoice(newVoice)
            }
        )
    }

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { settings.appleVoiceID },
            set: { newVoice in
                settings.appleVoiceID = newVoice
                controller?.setVoice(newVoice)
            }
        )
    }
}

/// A tappable paper swatch showing a theme's background + a sample glyph in its
/// ink color, ringed when selected.
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
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 2.5 : 1)
                )
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A font-family row rendered in its own typeface, with a checkmark when active.
private struct FontRow: View {
    let font: ReaderFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(font.displayName)
                    .font(Font(font.uiFont(size: 18)))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .font(.body.weight(.semibold))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
