import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One-time YouTube subscription import. Two sources, presented together:
/// a logged-in `feed/channels` DOM harvest (primary) and a Google Takeout
/// `subscriptions.csv` (robust fallback). Both land in the same checkbox picker;
/// selected channels are subscribed as RSS feeds via the wave-1 machinery.
///
/// Presented as a sheet from `FeedsView`. The harvest path opens `SiteLoginView`
/// on YouTube first so the user's Google session lands in the shared cookie jar;
/// the harvest then runs on dismiss. Failure states are honest and always point
/// at the CSV path — never an endless spinner (mirrors `SiteLoginsView`).
struct YouTubeImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]

    @State private var model = YouTubeImportModel()
    @State private var showingLogin = false
    @State private var showingFileImporter = false

    private var existingChannelIDs: Set<String> {
        YouTubeImportModel.existingChannelIDs(in: feeds)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import Subscriptions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .sheet(isPresented: $showingLogin, onDismiss: {
                    Task { await model.runHarvest(existingChannelIDs: existingChannelIDs) }
                }) {
                    if let url = URL(string: "https://www.youtube.com/feed/channels") {
                        SiteLoginView(url: url)
                    }
                }
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.commaSeparatedText, .plainText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            model.importCSV(from: url, existingChannelIDs: existingChannelIDs)
                        }
                    case .failure:
                        break // user cancelled or picker failed; stay on source screen
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .chooseSource:
            sourceChooser
        case .harvesting:
            ProgressView("Reading your subscriptions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .picking:
            picker
        case .subscribing:
            ProgressView("Subscribing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let added):
            doneView(added: added)
        case .failure(let message):
            failureView(message)
        }
    }

    // MARK: - Source chooser

    private var sourceChooser: some View {
        List {
            Section {
                Button {
                    showingLogin = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import from YouTube").font(.headline)
                            Text("Sign in and we'll read your subscribed channels.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
                    }
                }
            }
            Section {
                Button {
                    showingFileImporter = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import from Google Takeout").font(.headline)
                            Text("Pick the subscriptions.csv from your Takeout export.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text.fill").foregroundStyle(.blue)
                    }
                }
            } footer: {
                Text("A one-time import — no ongoing sync. Channels become normal feeds you can unsubscribe any time.")
            }
        }
    }

    // MARK: - Picker

    private var picker: some View {
        Group {
            if model.newChannels.isEmpty {
                ContentUnavailableView {
                    Label("Nothing New to Import", systemImage: "checkmark.circle")
                } description: {
                    Text(model.alreadySubscribedCount > 0
                        ? "All \(model.alreadySubscribedCount) channels we found are already in your feeds."
                        : "No channels were found to import.")
                }
            } else {
                List {
                    Section {
                        ForEach(model.newChannels) { channel in
                            Button {
                                model.toggle(channel)
                            } label: {
                                HStack {
                                    Image(systemName: model.isSelected(channel) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.isSelected(channel) ? Color.accentColor : Color.secondary)
                                    Text(channel.title).foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("^[\(model.newChannels.count) channel](inflect: true)")
                    } footer: {
                        if model.alreadySubscribedCount > 0 {
                            Text("\(model.alreadySubscribedCount) already in your feeds.")
                        }
                    }
                }
            }
        }
        .toolbar {
            if !model.newChannels.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.allSelected ? "Deselect All" : "Select All") {
                        if model.allSelected { model.deselectAll() } else { model.selectAll() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await model.subscribeSelected(context: context) }
                    } label: {
                        Text(model.selection.isEmpty
                            ? "Subscribe"
                            : "Subscribe to ^[\(model.selection.count) channel](inflect: true)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubscribe)
                }
            }
        }
    }

    // MARK: - Terminal states

    private func doneView(added: Int) -> some View {
        ContentUnavailableView {
            Label("Import Complete", systemImage: "checkmark.circle.fill")
        } description: {
            Text(added > 0
                ? "Subscribed to ^[\(added) channel](inflect: true)."
                : "No new channels were subscribed.")
            if model.failedCount > 0 {
                Text("\(model.failedCount) couldn't be reached and were skipped.")
            }
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Import Didn't Work", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Google Takeout") { showingFileImporter = true }
                .buttonStyle(.borderedProminent)
            Button("Back") { model.reset() }
        }
    }
}
