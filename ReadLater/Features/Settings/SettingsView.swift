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
    @State private var apiKeyStatus: String?
    @State private var apiKeyStatusIsError = false
    @State private var hasStoredKey = false
    @State private var showingFolderPicker = false
    @State private var lastExportStatus: String?
    private let syncStatus = SyncStatus.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: syncStatus.isSyncing ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(syncStatus.isSyncing ? .green : .secondary)
                    Text(syncStatus.summary)
                    Spacer()
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                if let detail = syncStatus.detail {
                    Text(detail)
                }
            }

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
                        ForEach(VoiceCatalog.appleVoices(), id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                case .openAI:
                    Picker("Voice", selection: $settings.openAIVoice) {
                        ForEach(VoiceCatalog.openAIVoices, id: \.self) { v in
                            Text(v.capitalized).tag(v)
                        }
                    }
                }
                Picker("Speed", selection: $settings.ttsRate) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Text(AudioPlayerBar.speedLabel(for: r)).tag(r)
                    }
                }
            }

            Section {
                if hasStoredKey {
                    HStack {
                        Text("OpenAI Key")
                        Spacer()
                        Text("sk-••••••••")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Key stored")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive, action: removeKey)
                    }
                } else {
                    SecureField("Paste API key (sk-…)", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(saveKey)
                    Button("Save Key", action: saveKey)
                        .disabled(trimmedKeyInput.isEmpty)
                }
                if let apiKeyStatus {
                    Text(apiKeyStatus)
                        .font(.footnote)
                        .foregroundStyle(apiKeyStatusIsError ? .red : .secondary)
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                if hasStoredKey {
                    Text("Swipe the key row to remove it. Only used when OpenAI is the active TTS provider.")
                } else {
                    Text("Stored in Keychain. Only used to synthesize speech when OpenAI is the active TTS provider.")
                }
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
                Picker("Appearance", selection: .init(
                    get: { settings.readerAppearance },
                    set: { settings.readerAppearance = $0 }
                )) {
                    ForEach(ReaderAppearance.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Font Size: \(Int(settings.readerFontSize)) pt")
                    Slider(value: $settings.readerFontSize, in: 12...32, step: 1)
                }
                Toggle("Block reader (beta)", isOn: $settings.useBlockReader)
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: refreshStoredKeyState)
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

    private var trimmedKeyInput: String {
        apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshStoredKeyState() {
        hasStoredKey = KeychainStore.get(account: KeychainStore.Account.openAI) != nil
    }

    private func saveKey() {
        let trimmed = trimmedKeyInput
        guard !trimmed.isEmpty else { return }

        guard KeychainStore.set(trimmed, account: KeychainStore.Account.openAI) else {
            apiKeyStatus = "Couldn't save key to Keychain."
            apiKeyStatusIsError = true
            hasStoredKey = false
            return
        }

        refreshStoredKeyState()
        if hasStoredKey {
            apiKeyInput = ""
            apiKeyStatus = nil
            apiKeyStatusIsError = false
        } else {
            apiKeyStatus = "Key didn't persist — try again."
            apiKeyStatusIsError = true
        }
    }

    private func removeKey() {
        KeychainStore.delete(account: KeychainStore.Account.openAI)
        hasStoredKey = false
        apiKeyInput = ""
        apiKeyStatus = nil
        apiKeyStatusIsError = false
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
