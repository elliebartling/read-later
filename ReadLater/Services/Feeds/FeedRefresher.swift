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

    /// Refreshes every subscription: feed documents download concurrently,
    /// merges run on the main actor.
    static func refreshAll(context: ModelContext) async {
        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        guard !feeds.isEmpty else { return }

        let targets = feeds.compactMap { feed in
            feed.feedURL.map { (feed.id, $0) }
        }
        var parsedByFeedID: [UUID: ParsedFeed] = [:]
        await withTaskGroup(of: (UUID, ParsedFeed?).self) { group in
            for (feedID, url) in targets {
                group.addTask {
                    (feedID, try? await FeedFetcher.fetch(feedURL: url))
                }
            }
            for await (feedID, parsed) in group {
                if let parsed { parsedByFeedID[feedID] = parsed }
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
        var existingByGuid: [String: FeedEntry] = [:]
        for entry in feed.allEntries {
            existingByGuid[entry.guid] = entry
        }

        for item in parsed.items {
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
            } else {
                let entry = FeedEntry(
                    feed: feed,
                    guid: item.id,
                    title: item.title,
                    url: item.url,
                    publishedAt: item.publishedAt,
                    summary: item.summary,
                    author: item.author
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
