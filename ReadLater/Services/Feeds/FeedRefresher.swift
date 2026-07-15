import Foundation
import SwiftData

/// Fetches subscribed feeds and merges their items into persisted `FeedEntry`
/// rows. Merging is idempotent: entries are keyed by guid (falling back to
/// URL), re-fetches never duplicate, and read state survives refreshes.
///
/// Deliberately callable from anywhere — a future background-refresh task
/// (`BGAppRefreshTask`) should just call `refreshAll(context:)`.
@MainActor
enum FeedRefresher {
    /// Per-feed cap. Far larger than any feed document (~20–50 items), so a
    /// pruned entry is never still present in the XML — if it were, the next
    /// refresh would resurrect it as unread.
    static let maxEntriesPerFeed = 300

    /// Refreshes one feed. Returns false when the fetch failed (existing
    /// entries are left untouched so the list still works offline).
    @discardableResult
    static func refresh(feed: Feed, context: ModelContext) async -> Bool {
        guard let url = feed.feedURL,
              let parsed = try? await FeedFetcher.fetch(feedURL: url)
        else { return false }
        merge(parsed: parsed, into: feed, context: context)
        try? context.save()
        return true
    }

    /// Refreshes every subscription. Non-Reddit feeds download concurrently;
    /// reddit.com-family feeds download sequentially with a polite spacing
    /// (`RedditPolicy`) because Reddit throttles anonymous fetches. A 429 on a
    /// Reddit fetch backs off and stops the sequential run — the remaining
    /// Reddit feeds keep their existing entries (non-fatal staleness). Merges
    /// run on the main actor.
    static func refreshAll(context: ModelContext) async {
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        guard !feeds.isEmpty else { return }

        let targets = feeds.compactMap { feed in
            feed.feedURL.map { (feed.id, $0) }
        }
        let (concurrent, sequential) = RedditPolicy.partition(targets.map(\.1))

        var parsedByFeedID: [UUID: ParsedFeed] = [:]

        // Concurrent group: everything that isn't Reddit.
        let concurrentSet = Set(concurrent.map(\.absoluteString))
        let concurrentTargets = targets.filter { concurrentSet.contains($0.1.absoluteString) }
        await withTaskGroup(of: (UUID, ParsedFeed?).self) { group in
            for (feedID, url) in concurrentTargets {
                group.addTask {
                    (feedID, try? await FeedFetcher.fetch(feedURL: url))
                }
            }
            for await (feedID, parsed) in group {
                if let parsed { parsedByFeedID[feedID] = parsed }
            }
        }

        // Sequential group: Reddit, one at a time with spacing. On 429, stop.
        let sequentialSet = Set(sequential.map(\.absoluteString))
        let sequentialTargets = targets.filter { sequentialSet.contains($0.1.absoluteString) }
        for (index, (feedID, url)) in sequentialTargets.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: RedditPolicy.refreshSpacing)
            }
            do {
                parsedByFeedID[feedID] = try await FeedFetcher.fetch(feedURL: url)
            } catch FeedFetcher.FetchError.rateLimited {
                NSLog("FeedRefresher: Reddit rate-limited (429) — backing off, %d feeds left stale",
                      sequentialTargets.count - index)
                break
            } catch {
                // Other failures are per-feed: skip this one, keep going.
                continue
            }
        }

        for feed in feeds {
            if let parsed = parsedByFeedID[feed.id] {
                merge(parsed: parsed, into: feed, context: context)
            }
        }
        try? context.save()
    }

    /// Merges parsed items into the feed's persisted entries. Caller saves.
    static func merge(parsed: ParsedFeed, into feed: Feed, context: ModelContext) {
        let isReddit = RedditFeed.isRedditURL(feed.feedURL)

        var existingByGuid: [String: FeedEntry] = [:]
        for entry in feed.allEntries {
            existingByGuid[entry.guid] = entry
        }

        for item in parsed.items {
            let reddit = redditFields(for: item, isReddit: isReddit)
            if let entry = existingByGuid[item.id] {
                // Feeds edit published posts; refresh content but never touch
                // read state. Assign only on change to avoid dirtying the row
                // (and re-syncing it) on every fetch.
                if !item.title.isEmpty, entry.title != item.title { entry.title = item.title }
                if let summary = item.summary, entry.summary != summary { entry.summary = summary }
                if let published = item.publishedAt, entry.publishedAt != published {
                    entry.publishedAt = published
                }
                if let author = item.author, entry.author != author { entry.author = author }
                if entry.externalURL != reddit.externalURL { entry.externalURL = reddit.externalURL }
                if entry.contentHTML != reddit.contentHTML { entry.contentHTML = reddit.contentHTML }
                if entry.thumbnailURL != item.thumbnailURL { entry.thumbnailURL = item.thumbnailURL }
            } else {
                let entry = FeedEntry(
                    feed: feed,
                    guid: item.id,
                    title: item.title,
                    url: item.url,
                    publishedAt: item.publishedAt,
                    summary: item.summary,
                    author: item.author,
                    externalURL: reddit.externalURL,
                    contentHTML: reddit.contentHTML,
                    thumbnailURL: item.thumbnailURL
                )
                context.insert(entry)
                existingByGuid[item.id] = entry
            }
        }

        feed.lastFetchedAt = .now
        if feed.title.isEmpty { feed.title = parsed.title }
        if feed.siteURL == nil { feed.siteURL = parsed.siteURL }

        prune(feed, context: context)
    }

    /// Cap on persisted Reddit self-post body HTML, so a pathologically long
    /// post can't bloat a CloudKit record. Comfortably above a normal post.
    static let maxRedditContentHTMLChars = 100_000

    /// Reddit-only derived fields for an item. For a link post, `externalURL` is
    /// the post's external destination and no body HTML is stored (the external
    /// article is parsed instead). For a self post, `externalURL` is nil and the
    /// body HTML is kept (capped) so it can render through the prefetched-HTML
    /// path. Non-Reddit feeds get (nil, nil). Pure — unit-testable directly.
    nonisolated static func redditFields(
        for item: ParsedFeedItem,
        isReddit: Bool
    ) -> (externalURL: URL?, contentHTML: String?) {
        guard isReddit else { return (nil, nil) }
        let external = RedditFeed.externalURL(fromContentHTML: item.contentHTML)
        if external != nil {
            // Link post: parse the external URL, no body to keep.
            return (external, nil)
        }
        // Self post: keep the (capped) body HTML for the prefetched-HTML render.
        let body = item.contentHTML.map { String($0.prefix(maxRedditContentHTMLChars)) }
        return (nil, body)
    }

    /// Keeps the newest `maxEntriesPerFeed` entries (by publication date,
    /// then first-seen date) and deletes the rest.
    private static func prune(_ feed: Feed, context: ModelContext) {
        let entries = feed.allEntries
        guard entries.count > maxEntriesPerFeed else { return }
        let sorted = entries.sorted {
            ($0.publishedAt ?? $0.fetchedAt) > ($1.publishedAt ?? $1.fetchedAt)
        }
        for entry in sorted.dropFirst(maxEntriesPerFeed) {
            context.delete(entry)
        }
    }
}
