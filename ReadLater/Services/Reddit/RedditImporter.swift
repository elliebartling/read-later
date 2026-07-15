import Foundation
import SwiftData

/// Pure planning for the saved-posts import: decide which saved posts become new
/// library items, dedupe them against what's already saved, and route each the
/// same way wave-1 routes a Reddit feed entry (self post → prefetched-HTML body;
/// link post → external URL; permalink → `discussionURL`). Network- and
/// store-free so the dedupe/routing is unit-testable with fixtures.
enum RedditImportPlan {

    /// One resolved import, ready to become a `PendingSave`.
    struct PlannedSave: Equatable {
        let url: URL
        let title: String
        /// Self-post body HTML for the prefetched-HTML parse path; nil for link
        /// posts (their external URL is parsed instead).
        let capturedHTML: String?
        let discussionURL: URL?
    }

    struct Plan: Equatable {
        var saves: [PlannedSave] = []
        /// Count of saved posts skipped because the library already has that URL
        /// (or the post carried no usable URL).
        var skipped = 0
    }

    /// Builds the import plan. `existingURLs` is the set of URL strings already
    /// in the library (normalized by the caller with ``normalize(_:)``); a saved
    /// post whose URL is already present is skipped so re-running the import
    /// never duplicates. Within one batch, later duplicates are skipped too.
    static func plan(savedPosts: [RedditSavedPost], existingURLs: Set<String>) -> Plan {
        var plan = Plan()
        var seen = existingURLs
        for post in savedPosts {
            guard let url = post.url else { plan.skipped += 1; continue }
            let key = normalize(url)
            guard !seen.contains(key) else { plan.skipped += 1; continue }
            seen.insert(key)
            plan.saves.append(PlannedSave(
                url: url,
                title: post.title,
                capturedHTML: post.isSelf ? post.selfTextHTML : nil,
                discussionURL: post.permalink
            ))
        }
        return plan
    }

    /// Normalizes a URL for dedup: lowercased host, no trailing slash, no
    /// fragment. Deliberately conservative so distinct posts never collide.
    static func normalize(_ url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.fragment = nil
        var s = comps?.url?.absoluteString ?? url.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        return s.lowercased()
    }
}

/// Executes Reddit imports against the store. Subreddit subscription reuses the
/// wave-1 Feed machinery; saved-post import writes `PendingSave`s that drain
/// through the existing ingest pipeline. Both are `@MainActor` because they
/// touch the `ModelContext`.
@MainActor
enum RedditImporter {

    /// Caps the first saved import so a huge history doesn't queue thousands of
    /// parses at once. Parsing is serialized by `PendingSaveIngest.parseChain`
    /// (single-slot WKWebView), so imports are inherently queued — but we still
    /// bound the first pull. Parse-on-open covers anything beyond this.
    static let defaultSavedImportCap = 300

    // MARK: - Subreddit subscription (wave-1 machinery)

    /// Subscribes to the given subreddits by inserting `Feed` rows keyed on the
    /// subreddit's `.rss` URL — the same model the manual "Add Feed" sheet
    /// creates. Deliberately does **not** fetch each feed's entries here: that
    /// would fire one throttled reddit.com RSS request per subreddit and trip
    /// Reddit's ~1-req/min anonymous limit. Entries populate on the next
    /// `FeedRefresher.refreshAll` (which spaces reddit.com fetches). Returns the
    /// number of new subscriptions created (already-subscribed ones are skipped).
    @discardableResult
    static func subscribe(to subreddits: [RedditSubreddit], context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let existingFeedURLs = Set(existing.compactMap { $0.feedURL?.absoluteString })
        var created = 0
        for sub in subreddits {
            guard let feedURL = sub.feedURL, !existingFeedURLs.contains(feedURL.absoluteString) else { continue }
            let feed = Feed(
                feedURL: feedURL,
                siteURL: URL(string: "https://\(RedditFeed.canonicalHost)/r/\(sub.name)/"),
                title: "r/\(sub.name)"
            )
            context.insert(feed)
            created += 1
        }
        try? context.save()
        return created
    }

    // MARK: - Saved-posts import (ingest pipeline)

    struct SavedImportResult: Equatable {
        let imported: Int
        let skipped: Int
    }

    /// Plans and materializes a saved-posts import: dedupes against existing
    /// `Article` URLs, writes a `PendingSave` per new post (routing self vs link
    /// exactly as wave-1 does), then drains so the stubs appear immediately and
    /// parse in the background off the shared serial parse chain.
    static func importSaved(_ posts: [RedditSavedPost], context: ModelContext) async -> SavedImportResult {
        let existingURLs = existingArticleURLKeys(context: context)
        let plan = RedditImportPlan.plan(savedPosts: posts, existingURLs: existingURLs)

        for save in plan.saves {
            let pending = PendingSave(
                url: save.url,
                title: save.title,
                capturedHTML: save.capturedHTML,
                source: .reddit,
                discussionURL: save.discussionURL
            )
            try? pending.write()
        }
        await PendingSaveIngest.drain(context: context)
        return SavedImportResult(imported: plan.saves.count, skipped: plan.skipped)
    }

    /// The set of normalized URL strings already in the library, for dedup.
    private static func existingArticleURLKeys(context: ModelContext) -> Set<String> {
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        return Set(articles.compactMap { $0.url.map(RedditImportPlan.normalize) })
    }
}
