import SwiftData
import SwiftUI

/// The item list for one subscribed feed. Items are fetched live and never
/// persisted — tapping one saves it through the same PendingSave pipeline the
/// Share Extension uses, so it becomes a regular Article (highlights, TTS,
/// Obsidian export) and opens in the reader.
struct FeedItemsView: View {
    let feed: Feed
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var context
    @State private var items: [ParsedFeedItem] = []
    @State private var savedByURL: [URL: Article] = [:]
    @State private var loadFailed = false
    @State private var isLoading = true
    /// Snapshot of `feed.lastViewedAt` taken before this visit updates it, so
    /// "new" markers reflect what was new when the screen opened.
    @State private var newSince: Date?

    var body: some View {
        List {
            if let message = emptyStateMessage {
                ContentUnavailableView(
                    message.title,
                    systemImage: message.icon,
                    description: message.description.map(Text.init)
                )
                .listRowSeparator(.hidden)
            }
            ForEach(items) { item in
                Button {
                    Task { await open(item) }
                } label: {
                    FeedItemRow(
                        item: item,
                        isSaved: item.url.map { savedByURL[$0] != nil } ?? false,
                        isNew: isNew(item)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
        .listStyle(.plain)
        .navigationTitle(feed.title.isEmpty ? (feed.feedURL?.host ?? "Feed") : feed.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task {
            newSince = feed.lastViewedAt
            await refresh()
        }
    }

    private var emptyStateMessage: (title: String, icon: String, description: String?)? {
        guard items.isEmpty else { return nil }
        if isLoading { return nil }
        if loadFailed {
            return ("Couldn't load feed", "wifi.exclamationmark",
                    "Pull down to try again.")
        }
        return ("No items", "tray", nil)
    }

    private func isNew(_ item: ParsedFeedItem) -> Bool {
        guard let newSince, let published = item.publishedAt else { return false }
        return published > newSince
    }

    private func refresh() async {
        guard let feedURL = feed.feedURL else {
            isLoading = false
            loadFailed = true
            return
        }
        do {
            let parsed = try await FeedFetcher.fetch(feedURL: feedURL)
            items = parsed.items
            loadFailed = false
            feed.lastFetchedAt = .now
            feed.lastViewedAt = .now
            if feed.title.isEmpty { feed.title = parsed.title }
            if feed.siteURL == nil { feed.siteURL = parsed.siteURL }
            try? context.save()
            reloadSavedArticles()
        } catch {
            // Keep any items from a previous refresh on transient failures.
            loadFailed = items.isEmpty
        }
        isLoading = false
    }

    /// Index of already-saved articles by URL, so rows can show a saved badge
    /// and re-taps reopen the existing article instead of saving a duplicate.
    private func reloadSavedArticles() {
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        var map: [URL: Article] = [:]
        for article in articles {
            if let url = article.url { map[url] = article }
        }
        savedByURL = map
    }

    private func open(_ item: ParsedFeedItem) async {
        guard let url = item.url else { return }
        if let existing = savedByURL[url] {
            path.append(existing)
            return
        }
        let pending = PendingSave(
            url: url,
            title: item.title.isEmpty ? nil : item.title,
            source: .rss
        )
        try? pending.write()
        await PendingSaveIngest.drain(context: context)
        // drain() returns once the stub Article exists; parsing continues in
        // the background while the reader shows its loading state.
        if let article = fetchArticle(id: pending.id) {
            savedByURL[url] = article
            path.append(article)
        }
    }

    private func fetchArticle(id: UUID) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct FeedItemRow: View {
    let item: ParsedFeedItem
    let isSaved: Bool
    let isNew: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isNew {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? (item.url?.absoluteString ?? "Untitled") : item.title)
                    .font(.headline)
                    .lineLimit(3)
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let published = item.publishedAt {
                        Text(published.formatted(.relative(presentation: .named)))
                    }
                    if let author = item.author {
                        Text(author).lineLimit(1)
                    }
                    if isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
