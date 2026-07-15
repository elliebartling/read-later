import SwiftData
import SwiftUI

/// Entry list backed by persisted `FeedEntry` rows — either one feed's
/// entries or the unified "All Items" river (`feed == nil`). Entries render
/// instantly from the store (works offline); a refresh runs on appear and on
/// pull. Tapping an entry marks it read and saves it through the PendingSave
/// pipeline, so it opens as a regular Article in the reader.
struct FeedEntriesView: View {
    private let feed: Feed?
    @Binding private var path: NavigationPath
    @Query private var entries: [FeedEntry]

    @Environment(\.modelContext) private var context
    @State private var savedByURL: [URL: Article] = [:]
    @State private var isRefreshing = true
    @State private var refreshFailed = false

    init(feed: Feed?, path: Binding<NavigationPath>) {
        self.feed = feed
        _path = path
        var descriptor = FetchDescriptor<FeedEntry>(sortBy: [
            SortDescriptor(\.publishedAt, order: .reverse),
            SortDescriptor(\.fetchedAt, order: .reverse),
        ])
        if let feedID = feed?.id {
            descriptor.predicate = #Predicate { $0.feed?.id == feedID }
        }
        _entries = Query(descriptor)
    }

    var body: some View {
        List {
            if entries.isEmpty, isRefreshing {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.top, 40)
                .listRowSeparator(.hidden)
                .accessibilityLabel("Loading")
            } else if let message = emptyStateMessage {
                ContentUnavailableView(
                    message.title,
                    systemImage: message.icon,
                    description: message.description.map(Text.init)
                )
                .listRowSeparator(.hidden)
            }
            ForEach(entries) { entry in
                Button {
                    Task { await open(entry) }
                } label: {
                    FeedEntryRow(
                        entry: entry,
                        showsFeedName: feed == nil,
                        isSaved: entry.url.map { savedByURL[$0] != nil } ?? false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityValue(entry.isRead ? Text("Read") : Text("Unread"))
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .swipeActions(edge: .leading) {
                    Button {
                        entry.isRead.toggle()
                        try? context.save()
                    } label: {
                        Label(entry.isRead ? "Unread" : "Read",
                              systemImage: entry.isRead ? "circle" : "checkmark.circle")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    markAllRead()
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .disabled(entries.allSatisfy(\.isRead))
                .accessibilityLabel("Mark All Read")
            }
        }
        .refreshable { await refresh() }
        .task {
            reloadSavedArticles()
            await refresh()
        }
    }

    private var title: String {
        guard let feed else { return "All Items" }
        return feed.title.isEmpty ? (feed.feedURL?.host ?? "Feed") : feed.title
    }

    private var emptyStateMessage: (title: String, icon: String, description: String?)? {
        guard entries.isEmpty, !isRefreshing else { return nil }
        if refreshFailed {
            return ("Couldn't load feed", "wifi.exclamationmark", "Pull down to try again.")
        }
        return ("No items", "tray", nil)
    }

    private func refresh() async {
        isRefreshing = true
        if let feed {
            refreshFailed = !(await FeedRefresher.refresh(feed: feed, context: context))
        } else {
            await FeedRefresher.refreshAll(context: context)
            refreshFailed = false
        }
        reloadSavedArticles()
        isRefreshing = false
    }

    private func markAllRead() {
        for entry in entries where !entry.isRead {
            entry.isRead = true
        }
        try? context.save()
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

    private func open(_ entry: FeedEntry) async {
        guard let permalink = entry.url else { return }
        entry.isRead = true
        try? context.save()

        // Reddit link posts save (and parse) the EXTERNAL article; self posts
        // and non-Reddit entries save their own URL. `entry.url` stays the
        // comments permalink in every case; Reddit entries also carry a
        // discussion link onto the resulting Article.
        let isReddit = RedditFeed.isRedditURL(permalink)
        let saveURL = entry.externalURL ?? permalink
        // Self post: render the stored post body through the prefetched-HTML
        // parse path instead of fetching the permalink page.
        let capturedHTML = (isReddit && entry.externalURL == nil) ? entry.contentHTML : nil
        let discussionURL = isReddit ? permalink : nil

        if let existing = savedByURL[saveURL] {
            path.append(existing)
            return
        }
        let pending = PendingSave(
            url: saveURL,
            title: entry.title.isEmpty ? nil : entry.title,
            capturedHTML: capturedHTML,
            source: .rss,
            discussionURL: discussionURL
        )
        try? pending.write()
        await PendingSaveIngest.drain(context: context)
        // drain() returns once the stub Article exists; parsing continues in
        // the background while the reader shows its loading state.
        if let article = fetchArticle(id: pending.id) {
            savedByURL[saveURL] = article
            path.append(article)
        }
    }

    private func fetchArticle(id: UUID) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct FeedEntryRow: View {
    let entry: FeedEntry
    let showsFeedName: Bool
    let isSaved: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .opacity(entry.isRead ? 0 : 1)
                .accessibilityHidden(true)
            if let thumbnailURL = entry.thumbnailURL {
                FeedThumbnail(url: thumbnailURL)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.isEmpty ? (entry.url?.absoluteString ?? "Untitled") : entry.title)
                    .font(.headline)
                    .lineLimit(3)
                    .foregroundStyle(entry.isRead ? .secondary : .primary)
                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if showsFeedName, let feedTitle = entry.feed?.title, !feedTitle.isEmpty {
                        Text(feedTitle).lineLimit(1)
                    }
                    if let published = entry.publishedAt {
                        Text(published.formatted(.relative(presentation: .named)))
                    }
                    if let author = entry.author {
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

/// Small 16:9 entry thumbnail (YouTube channel videos), loaded and downsampled
/// through the shared `ArticleImageCache` so scrolling doesn't re-fetch.
private struct FeedThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    private static let width: CGFloat = 88
    private static let height: CGFloat = 49 // 16:9

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            image = await ArticleImageCache.shared.image(for: url, targetWidth: Self.width)
        }
    }
}
