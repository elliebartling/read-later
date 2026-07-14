import Foundation
import SwiftData

// CloudKit-backed SwiftData requires every attribute to be optional or carry
// an inline default, and every relationship to be optional — otherwise
// ModelContainer creation throws at launch. Keep that invariant when adding
// properties to any synced model.
@Model
final class Feed {
    var id: UUID = UUID()
    /// The feed document itself (RSS/Atom XML), not the site homepage.
    var feedURL: URL?
    /// The human-facing site the feed belongs to (channel <link> / Atom alternate).
    var siteURL: URL?
    var title: String = ""
    var subscribedAt: Date = Date.now
    var lastFetchedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \FeedEntry.feed)
    var entries: [FeedEntry]?

    var allEntries: [FeedEntry] { entries ?? [] }

    init(
        id: UUID = UUID(),
        feedURL: URL,
        siteURL: URL? = nil,
        title: String = "",
        subscribedAt: Date = .now
    ) {
        self.id = id
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.title = title
        self.subscribedAt = subscribedAt
    }
}
