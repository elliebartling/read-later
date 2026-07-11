import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query private var settingsRows: [AppSettings]

    var body: some View {
        NavigationStack {
            // A single AppSettings row is seeded at startup (RootView). Never
            // insert here — inserting during body evaluation is a SwiftUI
            // anti-pattern and double-inserts under concurrent evaluation.
            if let settings = settingsRows.first {
                SettingsForm(settings: settings)
            } else {
                ProgressView()
                    .navigationTitle("Settings")
            }
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var context
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: String = ""
    @State private var showingFolderPicker = false
    @State private var lastExportStatus: String?

    private static let openAIVoices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]

    /// English voices first, then everything else, both alphabetized.
    private var appleVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            let lhsEnglish = $0.language.hasPrefix("en")
            let rhsEnglish = $1.language.hasPrefix("en")
            if lhsEnglish != rhsEnglish { return lhsEnglish }
            return ($0.language, $0.name) < ($1.language, $1.name)
        }
    }

    var body: some View {
        Form {
            Section("Read Aloud") {
                Picker("Provider", selection: $settings.ttsProvider) {
                    ForEach(TTSProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                switch settings.ttsProvider {
                case .apple:
                    Picker("Voice", selection: $settings.appleVoiceID) {
                        Text("System Default").tag("")
                        ForEach(appleVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                case .openAI:
                    Picker("Voice", selection: $settings.openAIVoice) {
                        ForEach(Self.openAIVoices, id: \.self) { v in
                            Text(v.capitalized).tag(v)
                        }
                    }
                }
            }

            Section {
                SecureField("sk-…", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save Key") { saveKey() }
                        .disabled(apiKeyInput.isEmpty)
                    Spacer()
                    Button("Clear", role: .destructive) { clearKey() }
                }
                if !apiKeyStatus.isEmpty {
                    Text(apiKeyStatus).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Stored in Keychain. Only used to synthesize speech when OpenAI is the active TTS provider.")
            }

            Section {
                Button {
                    showingFolderPicker = true
                } label: {
                    HStack {
                        Text("Choose Vault Folder…")
                        Spacer()
                        if settings.obsidianBookmarkData != nil {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                TextField("Sub-folder", text: $settings.obsidianSubfolder)
                    .autocorrectionDisabled()
                Button("Export All Articles") { exportAll() }
                if let status = lastExportStatus {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Obsidian Export")
            } footer: {
                Text("Pick any folder in Files — iCloud Drive, Dropbox, local, etc. The app only rewrites the marked section of each note, so your own edits in exported notes are preserved.")
            }

            Section("Reader") {
                Picker("Theme", selection: $settings.readerTheme) {
                    ForEach(ReaderTheme.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                Stepper("Font Size: \(Int(settings.readerFontSize))",
                        value: $settings.readerFontSize,
                        in: 14...28)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            if KeychainStore.get(account: KeychainStore.Account.openAI) != nil {
                apiKeyStatus = "Key on file."
            }
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try ObsidianExporter.setDestination(url, in: settings)
                    try? context.save()
                    lastExportStatus = "Destination set."
                } catch {
                    lastExportStatus = "Couldn't save destination: \(error.localizedDescription)"
                }
            case .failure(let err):
                lastExportStatus = "Folder pick failed: \(err.localizedDescription)"
            }
        }
    }

    private func saveKey() {
        KeychainStore.set(apiKeyInput, account: KeychainStore.Account.openAI)
        apiKeyStatus = "Key saved."
        apiKeyInput = ""
    }

    private func clearKey() {
        KeychainStore.delete(account: KeychainStore.Account.openAI)
        apiKeyStatus = "Key cleared."
    }

    private func exportAll() {
        do {
            try ObsidianExporter.exportAll(context: context, settings: settings)
            lastExportStatus = "Exported all articles."
        } catch {
            lastExportStatus = "Export failed: \(error.localizedDescription)"
        }
    }
}
