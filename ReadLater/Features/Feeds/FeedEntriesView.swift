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
    @State private var isRefreshing = true
    @State private var refreshFailed = false
    @State private var confirmingMarkAllRead = false

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
            ForEach(entries) { entry in
                // **R6.** A real `NavigationLink`, with the system disclosure.
                // These were `Button`s because opening an entry has to *create*
                // its destination (save → parse → Article) before it can show
                // it; `FeedEntryReader` moves that work behind the push, so the
                // row is an ordinary link and the list's grammar matches
                // Library's instead of being the one list with no chevron.
                NavigationLink(value: FeedEntryPassage(entry: entry)) {
                    FeedEntryRow(entry: entry, showsFeedName: feed == nil)
                }
                .readableRowStyle()
                .swipeActions(edge: .leading) {
                    Button {
                        entry.isRead.toggle()
                        try? context.save()
                    } label: {
                        Label(entry.isRead ? "Unread" : "Read",
                              icon: entry.isRead ? .circle : .checkCircle)
                    }
                }
            }
        }
        .pageList()
        // **E1.** One centred overlay for loading, empty and failed — three
        // list-row placements before this.
        .overlay {
            if entries.isEmpty, isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading")
            } else {
                emptyState
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // A feed (or All Items) is a layer-1 root reached from the sidebar, so
        // its leading slot peels back to the sidebar (#57).
        .sidebarBackToolbarItem()
        .navigationDestination(for: FeedEntryPassage.self) { passage in
            FeedEntryReader(entry: passage.entry)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    confirmingMarkAllRead = true
                } label: {
                    Image(.checkCircle).uiGlyph()
                }
                .disabled(entries.allSatisfy(\.isRead))
                .accessibilityLabel("Mark all read")
            }
        }
        // Ellen, build-44 review: *"what is the checkmark?"* — a bare circled
        // check in the trailing slot with nothing on screen to name it. It is
        // the platform's mark-all-read verb, and now the only checkmark in the
        // list (the row-level "Saved" field is gone), but a glyph nobody can
        // read is still a glyph nobody can read. The confirmation names the
        // action at the point of use, which is the cheapest place to put the
        // label without adding a second toolbar vocabulary — and it stops one
        // stray tap from clearing 132 unread flags with no way back.
        .confirmationDialog(
            "Mark all items read?",
            isPresented: $confirmingMarkAllRead,
            titleVisibility: .visible
        ) {
            Button("Mark all read") { markAllRead() }
            Button("Cancel", role: .cancel) {}
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var title: String {
        guard let feed else { return "All Items" }
        return feed.title.isEmpty ? (feed.feedURL?.host ?? "Feed") : feed.title
    }

    /// **E2/E3.** One sentence naming the mechanism. A *failed* refresh is a
    /// failure state and takes `Semantic.warning`; an empty-but-healthy feed
    /// gets no colour at all.
    private var emptyState: EmptyStateView? {
        guard entries.isEmpty, !isRefreshing else { return nil }
        if refreshFailed {
            return EmptyStateView(
                mark: .wifiSlash,
                title: "Couldn't load",
                message: "The feed didn't answer. Pull down to try again.",
                isFailure: true
            )
        }
        return EmptyStateView(
            mark: .tray,
            title: "Nothing new",
            message: feed == nil
                ? "New items from your subscriptions collect here as they publish."
                : "This feed hasn't published anything yet. Pull down to check again."
        )
    }

    private func refresh() async {
        isRefreshing = true
        if let feed {
            refreshFailed = !(await FeedRefresher.refresh(feed: feed, context: context))
        } else {
            await FeedRefresher.refreshAll(context: context)
            refreshFailed = false
        }
        isRefreshing = false
    }

    private func markAllRead() {
        for entry in entries where !entry.isRead {
            entry.isRead = true
        }
        try? context.save()
    }

    /// Whether an already-saved article for a re-tapped entry can be reopened
    /// directly. A `.failed` article must instead re-parse through the router,
    /// so a transient failure (a YouTube watch page that cancelled its first
    /// navigation, a flaky fetch) can re-route and recover rather than trapping
    /// the entry on the "couldn't parse" screen. Pure so it is unit-testable.
    static func shouldReuseExisting(_ article: Article) -> Bool {
        article.parseStatus != .failed
    }
}

/// The navigation value for "open this entry". A struct rather than the entry
/// itself so the destination reads as what it is: a passage from a feed item to
/// the article it becomes.
struct FeedEntryPassage: Hashable {
    let entry: FeedEntry
}

/// **R6's other half.** Opening a feed entry has to *create* its destination —
/// save the URL, drain it through the pending-save pipeline, then show the
/// resulting `Article` — which is why these rows were `Button`s. Doing that work
/// behind the push instead of in front of it makes the row an ordinary
/// `NavigationLink` and, incidentally, makes the tap feel instant: the reader's
/// own loading state covers the save, which it already had to cover parsing.
///
/// Every rule the old `open(_:)` encoded is preserved verbatim — Reddit link
/// posts save the external article while the permalink stays the discussion
/// link, self posts render their captured HTML rather than re-fetching the
/// comments page, and a previously-failed article re-parses through the router
/// instead of reopening onto its own failure screen.
struct FeedEntryReader: View {
    let entry: FeedEntry

    @Environment(\.modelContext) private var context
    @State private var article: Article?
    @State private var didResolve = false

    var body: some View {
        Group {
            if let article {
                ReaderView(article: article)
            } else if didResolve {
                // The entry had no URL, or the save produced no article. Never
                // a blank screen (E2/E3).
                EmptyStateView(
                    mark: .warning,
                    title: "Couldn't open",
                    message: "This item has no readable link.",
                    isFailure: true
                )
                .pageBackground()
                // I1 — these two branches are pushed screens in their own
                // right, so they need the caret too. It goes on the branches
                // rather than on the `Group`, because the third branch is
                // `ReaderView`, which already carries it — one leading slot,
                // one caret.
                .phosphorBackButton()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pageBackground()
                    .accessibilityLabel("Opening")
                    .phosphorBackButton()
            }
        }
        .task {
            guard !didResolve else { return }
            await resolve()
            didResolve = true
        }
    }

    private func resolve() async {
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

        if let existing = existingArticle(for: saveURL) {
            if FeedEntriesView.shouldReuseExisting(existing) {
                article = existing
                return
            }
            // A previously-failed article (e.g. a video whose first parse hit a
            // transient navigation cancel) must re-parse through the router so
            // it can re-route. Reset to .pending so the reader shows its
            // spinner, show it, then re-parse in place.
            existing.parseStatus = .pending
            try? context.save()
            article = existing
            await PendingSaveIngest.reparse(article: existing, context: context)
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
        article = fetchArticle(id: pending.id)
    }

    private func existingArticle(for url: URL) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.url == url })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchArticle(id: UUID) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// A feed entry as a `ReadableRow` (§8.1) — the same component Library and
/// Search render, so "things you might read" finally look like one class of
/// thing across the app.
private struct FeedEntryRow: View {
    let entry: FeedEntry
    /// False in a per-feed list, where the feed name is the nav title (R2).
    let showsFeedName: Bool

    var body: some View {
        ReadableRow(
            // R1 (amended) — one unread signal, and it is the quietest one
            // available. The 8pt leading dot is gone; what remains is the read
            // row receding (title tone + faded thumbnail). No added chrome.
            isUnread: !entry.isRead,
            title: entry.title.isEmpty ? (entry.url?.absoluteString ?? "Untitled") : entry.title,
            summary: entry.summary,
            metadata: metadata,
            // R4 — the slot is reserved on every row in the list, so a feed
            // that mixes items with and without images keeps an even rhythm.
            reservesThumbnail: true,
            thumbnailURL: entry.thumbnailURL
        ) {
            // BR1/BR2 — All Items mixes sources, so each row carries its own
            // identity mark. A per-feed list is one source by definition, so
            // the mark would repeat on every row and is omitted.
            if showsFeedName { faviconTile }
        }
    }

    @ViewBuilder
    private var faviconTile: some View {
        let feed = entry.feed
        FaviconTile(
            host: feed?.siteURL?.host ?? feed?.feedURL?.host,
            title: feed?.sidebarDisplayTitle,
            tint: feed.map { FeedSourceKind.kind(for: $0).tint } ?? Source.website
        )
    }

    /// **R2.** `source · relative date`, `" · "` joined.
    ///
    /// Three fields the old row printed are gone. `author` duplicated the nav
    /// title on every row of a per-feed list (all 14 of them, in the audit) and
    /// has no slot in the fixed field order. The "Saved" *badge* was a glyph +
    /// label that wrapped mid-word into "Save" / "d" (T8), and wave 2 demoted
    /// it to a plain third field.
    ///
    /// **"Saved" itself is now gone too** *(Ellen, build-44 review: "why does
    /// it say saved?")*. The honest answer was: for no reason the row was not
    /// already giving. Opening a feed entry is what saves it, so on this screen
    /// "saved" and "read" are the same fact in almost every case — and read is
    /// already carried by the row's tone (R1, amended: regular weight,
    /// `Ink.secondary` title, thumbnail at 0.7). A second, wordier encoding of
    /// a state the row already renders is exactly what N3 deletes, and it is
    /// the same call R1 made when it deleted the unread rail: *the title tone
    /// already carried the fact.*
    ///
    /// The edge cases where the two diverge — mark-all-read without opening,
    /// or the same URL saved from the share sheet — do not earn a permanent
    /// field on every row; the entry opens onto the article it already has
    /// either way, which is the only behaviour the badge was protecting.
    ///
    /// Deleting it also deletes the `@Query private var savedArticles: [Article]`
    /// this view kept purely to compute it: every feed list was fetching the
    /// entire article table and building a URL map on each render to decide
    /// whether to print one word.
    private var metadata: RowMetadata {
        RowMetadata(
            source: showsFeedName ? entry.feed?.sidebarDisplayTitle : nil,
            date: entry.publishedAt
        )
    }
}
