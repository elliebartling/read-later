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
                // **I5.** Settings rows get no icons. The audit found three
                // different icon treatments in the first three sections —
                // a monochrome grey cloud, a tinted blue person-key, then no
                // icons at all — which is most of why Settings reads as three
                // apps stacked. The label already carries the meaning (N3).
                HStack {
                    Text(syncStatus.summary)
                    Spacer()
                }
            } header: {
                Text("iCloud sync")
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
                    // I5 — no row icon. T7 — sentence case.
                    Text("Site logins")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Sites you've signed into to read member-only articles. Sign out to clear a site's cookies on this device.")
            }

            Section("Read aloud") {
                Picker("Provider", selection: $settings.ttsProvider) {
                    ForEach(TTSProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                switch settings.ttsProvider {
                case .apple:
                    Picker("Voice", selection: $settings.appleVoiceID) {
                        Text("System default").tag("")
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
                            .foregroundStyle(Ink.secondary)
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
                        .foregroundStyle(apiKeyStatusIsError ? Semantic.destructive : Ink.secondary)
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
                        // T7 — sentence case throughout Settings.
                        Text("Choose vault folder…")
                        Spacer()
                        // I5 — no glyph: the chosen state is said in words.
                        if settings.obsidianBookmarkData != nil {
                            Text("Chosen")
                                .font(.footnote)
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                }
                TextField("Sub-folder", text: $settings.obsidianSubfolder)
                    .autocorrectionDisabled()
                Button("Export all articles") { exportAll() }
                if let status = lastExportStatus {
                    Text(status).font(.footnote).foregroundStyle(Ink.secondary)
                }
            } header: {
                Text("Obsidian export")
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
                    Text("Font size: \(Int(settings.readerFontSize)) pt")
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
                            Text("Reddit account")
                            Spacer()
                            if let account = reddit.account {
                                Text("u/\(account.name)")
                                    .font(.footnote)
                                    .foregroundStyle(Ink.secondary)
                            } else {
                                Text("Sign in")
                                    .font(.footnote)
                                    .foregroundStyle(Ink.secondary)
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
        .pageForm()
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
                    Image(systemName: "exclamationmark.triangle")
                        .uiGlyph(size: Font.GlyphSize.subheadline)
                        .foregroundStyle(Semantic.destructive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export failed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Semantic.destructive)
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(Ink.secondary)
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
                        .foregroundStyle(Ink.secondary)
                } else {
                    Text("No events yet")
                        .font(.caption)
                        .foregroundStyle(Ink.secondary)
                }
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ink.secondary)
            }
        }
    }

    /// The sync event's status. Not a settings-row icon (I5): this is the
    /// row's *value* — a developer-facing readout with no text equivalent —
    /// so it keeps a glyph while every decorative Settings icon loses one.
    /// **I3** is honoured: unresolved states are outline, resolved states are
    /// filled, never mixed within the group.
    @ViewBuilder
    private var statusIcon: some View {
        Group {
            if let record {
                if !record.isFinished {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Ink.secondary)
                } else if record.succeeded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Semantic.success)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Semantic.destructive)
                }
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(Ink.secondary)
            }
        }
        .uiGlyph(size: Font.GlyphSize.body)
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
