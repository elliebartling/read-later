import SwiftData
import SwiftUI

/// Navigation marker for the unified "All Items" river.
private struct AllItemsRoute: Hashable {}

struct FeedsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(filter: #Predicate<FeedEntry> { $0.isRead == false })
    private var unreadEntries: [FeedEntry]
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
                } else {
                    NavigationLink(value: AllItemsRoute()) {
                        HStack {
                            Label("All Items", systemImage: "tray.full")
                                .font(.headline)
                            Spacer()
                            UnreadBadge(count: unreadEntries.count)
                        }
                        .padding(.vertical, 4)
                    }
                    Section("Subscriptions") {
                        ForEach(feeds) { feed in
                            NavigationLink(value: feed) {
                                FeedRow(feed: feed, unreadCount: unreadCount(for: feed))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(feed) } label: {
                                    Label("Unsubscribe", systemImage: "trash")
                                }
                            }
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
            .navigationDestination(for: AllItemsRoute.self) { _ in
                FeedEntriesView(feed: nil, path: $path)
            }
            .navigationDestination(for: Feed.self) { feed in
                FeedEntriesView(feed: feed, path: $path)
            }
            .navigationDestination(for: Article.self) { article in
                ReaderView(article: article)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddFeedSheet()
            }
        }
    }

    private func unreadCount(for feed: Feed) -> Int {
        unreadEntries.filter { $0.feed?.id == feed.id }.count
    }

    private func delete(_ feed: Feed) {
        context.delete(feed) // cascades to its entries
        try? context.save()
    }
}

private struct FeedRow: View {
    let feed: Feed
    let unreadCount: Int

    var body: some View {
        HStack {
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
            Spacer()
            UnreadBadge(count: unreadCount)
        }
        .padding(.vertical, 4)
    }
}

private struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("\(count) unread")
        }
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
                    .submitLabel(.go)
                    .onSubmit {
                        guard !isResolving, canSubscribe else { return }
                        Task { await subscribe() }
                    }
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
                        .disabled(!canSubscribe)
                    }
                }
            }
        }
    }

    /// Accepts bare domains ("daringfireball.net") by defaulting to https, and
    /// the Reddit `r/name` shorthand (→ the subreddit's Atom feed). Sort
    /// variants and full URLs pass through literally.
    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let subreddit = RedditFeed.normalizeSubredditShorthand(trimmed) {
            return subreddit
        }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    /// The Subscribe button is enabled for a normal URL/shorthand OR a YouTube
    /// channel reference (a `@handle` has no dot/scheme, so `normalizedURL`
    /// alone wouldn't recognise it).
    private var canSubscribe: Bool {
        normalizedURL != nil || YouTubeChannel.reference(from: urlString) != nil
    }

    private func subscribe() async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            // YouTube channel URLs / @handles resolve to the channel's Atom feed
            // (videos.xml?channel_id=…) before the normal feed resolver runs.
            // Returns nil for non-channel input, which falls through untouched.
            let channelFeedURL = try await YouTubeChannel.resolveFeedURL(from: urlString)
            guard let url = channelFeedURL ?? normalizedURL else { return }
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
            context.insert(feed)
            // Seed entries from the document we already fetched, so the feed
            // has content the moment the sheet closes.
            FeedRefresher.merge(parsed: resolved.parsed, into: feed, context: context)
            try? context.save()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't reach that URL."
        }
    }
}
