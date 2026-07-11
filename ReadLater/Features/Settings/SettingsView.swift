import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @State private var apiKeyInput = ""
    @State private var apiKeyStatus: String = ""
    @State private var showingFolderPicker = false
    @State private var lastExportStatus: String?

    private var settings: AppSettings {
        if let s = settingsRows.first { return s }
        let s = AppSettings()
        context.insert(s)
        try? context.save()
        return s
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Read Aloud") {
                    Picker("Provider", selection: $settings.ttsProvider) {
                        ForEach(TTSProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    TextField("Voice ID", text: $settings.ttsVoice)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                    Text("Pick any folder in Files — iCloud Drive, Dropbox, local, etc. Markdown notes will land in \(settings.obsidianSubfolder.isEmpty ? "the root" : "\"\(settings.obsidianSubfolder)/\"").")
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
