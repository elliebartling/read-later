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
    @State private var reddit = RedditAuthController.shared
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

            if syncStatus.isSyncing {
                syncDiagnosticsSection
            }

            Section {
                NavigationLink {
                    SiteLoginsView()
                } label: {
                    Label("Site Logins", systemImage: "person.badge.key")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Sites you've signed into to read member-only articles. Sign out to clear a site's cookies on this device.")
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

            Section {
                // "Sign in with Reddit" (wave 2). Only shown once a client ID is
                // configured (RedditAuthConfig.clientID); an unconfigured build
                // hides the whole account row so there's no dead button.
                if reddit.isConfigured {
                    NavigationLink {
                        RedditAccountView()
                    } label: {
                        HStack {
                            Label("Reddit Account", systemImage: "person.crop.circle.badge.checkmark")
                            Spacer()
                            if let account = reddit.account {
                                Text("u/\(account.name)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Sign In")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Picker("Open discussions in", selection: .init(
                    get: { settings.redditDiscussionApp },
                    set: { settings.redditDiscussionApp = $0 }
                )) {
                    ForEach(RedditDiscussionApp.allCases) { app in
                        Text(app.displayName).tag(app)
                    }
                }
            } header: {
                Text("Reddit")
            } footer: {
                Text("Where the reader's \u{201C}View discussion\u{201D} button opens a Reddit comments link. System Default uses the official Reddit app if installed, otherwise Safari.")
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

    /// Diagnostics for live CloudKit mirroring. Only shown while syncing; this
    /// is a developer-facing readout (setup/import/export events, counts, and
    /// any export error) but harmless to ship since Release never reaches sync.
    @ViewBuilder
    private var syncDiagnosticsSection: some View {
        Section {
            if let exportError = syncStatus.exportFailureText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export failed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            ForEach(SyncStatus.SyncEventKind.allCases) { kind in
                SyncEventRow(
                    kind: kind,
                    record: syncStatus.lastEvents[kind],
                    count: syncStatus.eventCounts[kind] ?? 0
                )
            }
        } header: {
            Text("Sync Diagnostics")
        } footer: {
            Text("Live iCloud mirroring events this session. If Export never appears or shows an error, the export engine isn't flushing records to CloudKit.")
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

/// One line in the Sync Diagnostics section: the event kind, its status
/// (pending / ✓ / ✗), how long ago it happened, and the session count.
private struct SyncEventRow: View {
    let kind: SyncStatus.SyncEventKind
    let record: SyncStatus.SyncEventRecord?
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label)
                if let record {
                    Text(timestamp(for: record))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No events yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let record {
            if !record.isFinished {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else if record.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func timestamp(for record: SyncStatus.SyncEventRecord) -> String {
        let date = record.endDate ?? record.startDate
        let relative = date.formatted(.relative(presentation: .named))
        if !record.isFinished {
            return "In progress · started \(relative)"
        }
        return relative
    }
}
