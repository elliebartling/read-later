import Foundation
import SwiftData

// CloudKit rules apply: attributes optional or defaulted, relationships optional.
@Model
final class FeedEntry {
    var id: UUID = UUID()
    var feed: Feed?
    /// Dedup key within a feed: the item's guid/id, falling back to its URL
    /// (`ParsedFeedItem.id` computes the same fallback at parse time).
    var guid: String = ""
    var title: String = ""
    var url: URL?
    var publishedAt: Date?
    var summary: String?
    var author: String?
    var isRead: Bool = false
    /// When this entry first appeared in a fetch — ordering fallback for
    /// feeds that omit publication dates, and the pruning tiebreaker.
    var fetchedAt: Date = Date.now
    /// For Reddit link posts: the post's external destination (extracted from
    /// the entry's content HTML). nil for self posts and every non-Reddit feed.
    /// Opening a link-post entry saves this URL through the normal parse
    /// pipeline while `url` stays the comments permalink. CloudKit-safe optional.
    var externalURL: URL?
    /// For Reddit self posts: the raw post-body HTML, so the entry can render
    /// through the prefetched-HTML parse path without a re-fetch. Only populated
    /// for Reddit self posts (link posts parse `externalURL` instead); nil
    /// everywhere else. CloudKit-safe optional.
    var contentHTML: String?
    /// Optional entry thumbnail (`media:thumbnail`). YouTube channel feeds carry
    /// one per video; ordinary RSS feeds usually don't, so it stays nil there.
    /// Rendered in the entry row when present. CloudKit-safe optional.
    var thumbnailURL: URL?

    init(
        id: UUID = UUID(),
        feed: Feed?,
        guid: String,
        title: String = "",
        url: URL? = nil,
        publishedAt: Date? = nil,
        summary: String? = nil,
        author: String? = nil,
        externalURL: URL? = nil,
        contentHTML: String? = nil,
        thumbnailURL: URL? = nil,
        fetchedAt: Date = .now
    ) {
        self.id = id
        self.feed = feed
        self.guid = guid
        self.title = title
        self.url = url
        self.publishedAt = publishedAt
        self.summary = summary
        self.author = author
        self.externalURL = externalURL
        self.contentHTML = contentHTML
        self.thumbnailURL = thumbnailURL
        self.isRead = false
        self.fetchedAt = fetchedAt
    }
}
