import SwiftData
import SwiftUI

struct FeedsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @State private var showingAddSheet = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if feeds.isEmpty {
                    ContentUnavailableView(
                        "No feeds yet",
                        systemImage: "dot.radiowaves.up.forward",
                        description: Text("Tap + and paste a site or feed URL to subscribe.")
                    )
                    .listRowSeparator(.hidden)
                }
                ForEach(feeds) { feed in
                    NavigationLink(value: feed) {
                        FeedRow(feed: feed)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(feed) } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Feeds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Feed.self) { feed in
                FeedItemsView(feed: feed, path: $path)
            }
            .navigationDestination(for: Article.self) { article in
                ReaderView(article: article)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddFeedSheet()
            }
        }
    }

    private func delete(_ feed: Feed) {
        context.delete(feed)
        try? context.save()
    }
}

private struct FeedRow: View {
    let feed: Feed

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(feed.title.isEmpty ? (feed.feedURL?.host ?? "Feed") : feed.title)
                .font(.headline)
                .lineLimit(2)
            if let host = feed.siteURL?.host ?? feed.feedURL?.host {
                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddFeedSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://example.com or feed URL", text: $urlString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(isResolving)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isResolving {
                        ProgressView()
                    } else {
                        Button("Subscribe") {
                            Task { await subscribe() }
                        }
                        .disabled(normalizedURL == nil)
                    }
                }
            }
        }
    }

    /// Accepts bare domains ("daringfireball.net") by defaulting to https.
    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func subscribe() async {
        guard let url = normalizedURL else { return }
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            let resolved = try await FeedFetcher.resolve(url: url)

            let existing = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
            if existing.contains(where: { $0.feedURL == resolved.feedURL }) {
                errorMessage = "You're already subscribed to this feed."
                return
            }

            let feed = Feed(
                feedURL: resolved.feedURL,
                siteURL: resolved.parsed.siteURL,
                title: resolved.parsed.title
            )
            feed.lastFetchedAt = .now
            context.insert(feed)
            try? context.save()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't reach that URL."
        }
    }
}
