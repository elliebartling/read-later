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

    init(
        id: UUID = UUID(),
        feed: Feed?,
        guid: String,
        title: String = "",
        url: URL? = nil,
        publishedAt: Date? = nil,
        summary: String? = nil,
        author: String? = nil,
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
        self.isRead = false
        self.fetchedAt = fetchedAt
    }
}
