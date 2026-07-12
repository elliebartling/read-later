import SwiftUI
import SwiftData

struct TypographyControls: View {
    @Bindable var settings: AppSettings
    /// Optional live controller so a voice change while listening applies
    /// immediately (restarts the current paragraph) rather than next start.
    var controller: TTSController? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Font") {
                    Picker("Family", selection: $settings.readerFontRaw) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.displayName).tag(font.rawValue)
                        }
                    }
                    Stepper("Size: \(Int(settings.readerFontSize))",
                            value: $settings.readerFontSize,
                            in: 14...28,
                            step: 1)
                }
                Section("Theme") {
                    Picker("Theme", selection: .init(
                        get: { settings.readerTheme },
                        set: { settings.readerTheme = $0 }
                    )) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
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
