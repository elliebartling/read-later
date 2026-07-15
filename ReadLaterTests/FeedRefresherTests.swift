import SwiftData
import XCTest
@testable import ReadLater

@MainActor
final class FeedRefresherTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([
            Article.self, Highlight.self, Tag.self,
            Feed.self, FeedEntry.self, AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    private func makeFeed() -> Feed {
        let feed = Feed(feedURL: URL(string: "https://example.com/feed.xml")!)
        context.insert(feed)
        return feed
    }

    private func makeItem(
        guid: String,
        title: String = "Title",
        urlString: String = "https://example.com/post",
        publishedAt: Date? = nil,
        summary: String? = nil
    ) -> ParsedFeedItem {
        var item = ParsedFeedItem()
        item.guid = guid
        item.title = title
        item.url = URL(string: urlString)
        item.publishedAt = publishedAt
        item.summary = summary
        return item
    }

    func testMergeInsertsNewEntries() {
        let feed = makeFeed()
        var parsed = ParsedFeed()
        parsed.title = "Example"
        parsed.siteURL = URL(string: "https://example.com/")
        parsed.items = [makeItem(guid: "a"), makeItem(guid: "b")]

        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try? context.save()

        XCTAssertEqual(feed.allEntries.count, 2)
        XCTAssertTrue(feed.allEntries.allSatisfy { !$0.isRead })
        XCTAssertNotNil(feed.lastFetchedAt)
    }

    func testMergeIsIdempotent() {
        let feed = makeFeed()
        var parsed = ParsedFeed()
        parsed.items = [makeItem(guid: "a"), makeItem(guid: "b")]

        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try? context.save()

        XCTAssertEqual(feed.allEntries.count, 2)
    }

    func testMergePreservesReadStateAndUpdatesContent() throws {
        let feed = makeFeed()
        var parsed = ParsedFeed()
        parsed.items = [makeItem(guid: "a", title: "Original", summary: "old")]
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)

        let entry = try XCTUnwrap(feed.allEntries.first)
        entry.isRead = true

        parsed.items = [makeItem(guid: "a", title: "Edited", summary: "new")]
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)

        XCTAssertEqual(feed.allEntries.count, 1)
        XCTAssertTrue(entry.isRead, "refresh must never reset read state")
        XCTAssertEqual(entry.title, "Edited")
        XCTAssertEqual(entry.summary, "new")
    }

    func testMergeFillsEmptyFeedMetadataOnly() {
        let feed = makeFeed()
        feed.title = "My Custom Name"
        var parsed = ParsedFeed()
        parsed.title = "Upstream Name"
        parsed.siteURL = URL(string: "https://example.com/")

        FeedRefresher.merge(parsed: parsed, into: feed, context: context)

        XCTAssertEqual(feed.title, "My Custom Name")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://example.com/")
    }

    func testMergePrunesOldestBeyondCap() {
        let feed = makeFeed()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var parsed = ParsedFeed()
        parsed.items = (0 ..< FeedRefresher.maxEntriesPerFeed + 20).map { i in
            makeItem(
                guid: "item-\(i)",
                urlString: "https://example.com/\(i)",
                publishedAt: base.addingTimeInterval(TimeInterval(i))
            )
        }

        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try? context.save()

        XCTAssertEqual(feed.allEntries.count, FeedRefresher.maxEntriesPerFeed)
        // The oldest items are the ones dropped.
        let survivingGuids = Set(feed.allEntries.map(\.guid))
        XCTAssertFalse(survivingGuids.contains("item-0"))
        XCTAssertTrue(survivingGuids.contains("item-\(FeedRefresher.maxEntriesPerFeed + 19)"))
    }

    /// Exercises the exact predicate shape FeedEntriesView's per-feed @Query
    /// uses — optional-chained relationship traversal is the most fragile
    /// SwiftData predicate form, so lock it down against a real store.
    func testScopedFetchByFeedIDReturnsOnlyThatFeedsEntries() throws {
        let feedA = makeFeed()
        let feedB = Feed(feedURL: URL(string: "https://other.com/feed.xml")!)
        context.insert(feedB)

        var parsedA = ParsedFeed()
        parsedA.items = [makeItem(guid: "a1"), makeItem(guid: "a2")]
        FeedRefresher.merge(parsed: parsedA, into: feedA, context: context)
        var parsedB = ParsedFeed()
        parsedB.items = [makeItem(guid: "b1")]
        FeedRefresher.merge(parsed: parsedB, into: feedB, context: context)
        try context.save()

        let feedID = feedA.id
        let descriptor = FetchDescriptor<FeedEntry>(
            predicate: #Predicate { $0.feed?.id == feedID },
            sortBy: [
                SortDescriptor(\.publishedAt, order: .reverse),
                SortDescriptor(\.fetchedAt, order: .reverse),
            ]
        )
        let scoped = try context.fetch(descriptor)
        XCTAssertEqual(Set(scoped.map(\.guid)), ["a1", "a2"])
    }

    func testDeletingFeedCascadesToEntries() throws {
        let feed = makeFeed()
        var parsed = ParsedFeed()
        parsed.items = [makeItem(guid: "a")]
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try context.save()

        context.delete(feed)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<FeedEntry>())
        XCTAssertTrue(remaining.isEmpty)
    }
}
