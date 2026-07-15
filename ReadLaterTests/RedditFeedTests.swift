import SwiftData
import XCTest
@testable import ReadLater

/// Reddit wave 1: link/self classification, `r/name` shorthand, host detection,
/// domain-aware serialization, Narwhal deep link, and the parse→merge pipeline.
/// Fixtures distill the real `r/<sub>/.rss` Atom shape (content HTML is
/// entity-encoded once, with Reddit's `[link]`/`[comments]` footer anchors).
final class RedditFeedTests: XCTestCase {

    // MARK: - Fixtures (distilled real Reddit Atom)

    /// A subreddit Atom feed with three posts: a self/text post, an external
    /// link post, and an image link post (i.redd.it). Inner attribute quotes are
    /// `&quot;` exactly as Reddit serializes them inside `type="html"` content.
    private let redditAtom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
      <category term="swift" label="r/swift"/>
      <title>Swift</title>
      <link rel="self" href="https://www.reddit.com/r/swift/.rss" type="application/atom+xml"/>
      <link rel="alternate" href="https://www.reddit.com/r/swift" type="text/html"/>
      <id>/r/swift/.rss</id>
      <entry>
        <author><name>/u/alice</name><uri>https://www.reddit.com/user/alice</uri></author>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class=&quot;md&quot;&gt;&lt;p&gt;This is a self post body with a &lt;a href=&quot;https://example.com/inline&quot;&gt;inline link&lt;/a&gt;.&lt;/p&gt;&lt;/div&gt;&lt;!-- SC_ON --&gt; &amp;#32; submitted by &amp;#32; &lt;a href=&quot;https://www.reddit.com/user/alice&quot;&gt; /u/alice &lt;/a&gt; &lt;br/&gt; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/aaa111/self_post/&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt; &amp;#32; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/aaa111/self_post/&quot;&gt;[comments]&lt;/a&gt;&lt;/span&gt;</content>
        <id>t3_aaa111</id>
        <link href="https://www.reddit.com/r/swift/comments/aaa111/self_post/" />
        <updated>2026-07-02T03:30:06+00:00</updated>
        <published>2026-07-02T03:30:06+00:00</published>
        <title>A self post</title>
      </entry>
      <entry>
        <author><name>/u/bob</name><uri>https://www.reddit.com/user/bob</uri></author>
        <content type="html">&lt;table&gt;&lt;tr&gt;&lt;td&gt;&lt;a href=&quot;https://blog.example.com/great-article&quot;&gt;&lt;img src=&quot;thumb.jpg&quot;&gt;&lt;/a&gt;&lt;/td&gt;&lt;td&gt; &amp;#32; submitted by &lt;a href=&quot;https://www.reddit.com/user/bob&quot;&gt; /u/bob &lt;/a&gt; &lt;br/&gt; &lt;span&gt;&lt;a href=&quot;https://blog.example.com/great-article&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt; &amp;#32; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/bbb222/great_article/&quot;&gt;[comments]&lt;/a&gt;&lt;/span&gt; &lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>
        <id>t3_bbb222</id>
        <link href="https://www.reddit.com/r/swift/comments/bbb222/great_article/" />
        <published>2026-07-03T10:00:00+00:00</published>
        <title>Great Article</title>
      </entry>
      <entry>
        <author><name>/u/carol</name></author>
        <content type="html">&lt;span&gt;&lt;a href=&quot;https://i.redd.it/abc123.png&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt; &amp;#32; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/ccc333/screenshot/&quot;&gt;[comments]&lt;/a&gt;&lt;/span&gt;</content>
        <id>t3_ccc333</id>
        <link href="https://www.reddit.com/r/swift/comments/ccc333/screenshot/" />
        <published>2026-07-04T10:00:00+00:00</published>
        <title>A screenshot</title>
      </entry>
    </feed>
    """

    /// Non-Reddit Atom counter-fixture: must behave exactly as before (no
    /// external URL, no reddit-specific body handling).
    private let plainAtom = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Plain Blog</title>
      <link rel="alternate" href="https://plain.example/"/>
      <entry>
        <title>A normal post</title>
        <link rel="alternate" href="https://plain.example/one"/>
        <id>tag:plain.example,2026:one</id>
        <published>2026-07-05T09:15:30Z</published>
        <content type="html">&lt;p&gt;Just a blog post with a &lt;a href=&quot;https://elsewhere.example&quot;&gt;link&lt;/a&gt;.&lt;/p&gt;</content>
      </entry>
    </feed>
    """

    // MARK: - Host detection

    func testIsRedditHost() {
        XCTAssertTrue(RedditFeed.isRedditHost("www.reddit.com"))
        XCTAssertTrue(RedditFeed.isRedditHost("reddit.com"))
        XCTAssertTrue(RedditFeed.isRedditHost("old.reddit.com"))
        XCTAssertTrue(RedditFeed.isRedditHost("m.reddit.com"))
        XCTAssertTrue(RedditFeed.isRedditURL(URL(string: "https://www.reddit.com/r/swift/.rss")))
        XCTAssertFalse(RedditFeed.isRedditHost("notreddit.com"))
        XCTAssertFalse(RedditFeed.isRedditHost("reddit.com.evil.com"))
        XCTAssertFalse(RedditFeed.isRedditHost(nil))
        XCTAssertFalse(RedditFeed.isRedditURL(URL(string: "https://example.com/feed")))
    }

    // MARK: - `r/name` shorthand

    func testShorthandNormalization() {
        let expected = "https://www.reddit.com/r/ios/.rss"
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("r/ios")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("/r/ios")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("r/ios/")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("reddit.com/r/ios")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("www.reddit.com/r/ios")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("https://www.reddit.com/r/ios")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("  R/iOS  ")?.absoluteString, expected)
        XCTAssertEqual(RedditFeed.normalizeSubredditShorthand("r/Swift_Lang")?.absoluteString,
                       "https://www.reddit.com/r/swift_lang/.rss")
    }

    func testShorthandLeavesSortVariantsAndOthersLiteral() {
        // Sort variants and explicit paths → not shorthand (nil = pass through).
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand("r/ios/top"))
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand("https://www.reddit.com/r/ios/top/.rss?t=week"))
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand("reddit.com/r/ios/.rss"))
        // Not a subreddit reference at all.
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand("example.com"))
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand("https://daringfireball.net/feeds/main"))
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand("u/someuser"))
        XCTAssertNil(RedditFeed.normalizeSubredditShorthand(""))
    }

    // MARK: - Link vs self classification

    func testExternalURLExtractionForLinkPost() throws {
        let feed = try FeedParser.parse(data: Data(redditAtom.utf8))
        let linkItem = try XCTUnwrap(feed.items.first { $0.title == "Great Article" })
        let external = RedditFeed.externalURL(fromContentHTML: linkItem.contentHTML)
        XCTAssertEqual(external?.absoluteString, "https://blog.example.com/great-article")
    }

    func testExternalURLNilForSelfPost() throws {
        let feed = try FeedParser.parse(data: Data(redditAtom.utf8))
        let selfItem = try XCTUnwrap(feed.items.first { $0.title == "A self post" })
        XCTAssertNil(RedditFeed.externalURL(fromContentHTML: selfItem.contentHTML))
    }

    func testExternalURLForImageLinkPost() throws {
        let feed = try FeedParser.parse(data: Data(redditAtom.utf8))
        let imageItem = try XCTUnwrap(feed.items.first { $0.title == "A screenshot" })
        let external = RedditFeed.externalURL(fromContentHTML: imageItem.contentHTML)
        XCTAssertEqual(external?.absoluteString, "https://i.redd.it/abc123.png")
    }

    func testExternalURLNilForEmptyOrMissingContent() {
        XCTAssertNil(RedditFeed.externalURL(fromContentHTML: nil))
        XCTAssertNil(RedditFeed.externalURL(fromContentHTML: ""))
        XCTAssertNil(RedditFeed.externalURL(fromContentHTML: "<p>no anchors here</p>"))
    }

    // MARK: - Parser captures content HTML

    func testParserCapturesContentHTMLForReddit() throws {
        let feed = try FeedParser.parse(data: Data(redditAtom.utf8))
        let selfItem = try XCTUnwrap(feed.items.first { $0.title == "A self post" })
        let html = try XCTUnwrap(selfItem.contentHTML)
        // Entity-decoded one level: real tags, not &lt;.
        XCTAssertTrue(html.contains("<div class=\"md\">"))
        XCTAssertTrue(html.contains("self post body"))
        // Plain summary still derived alongside.
        XCTAssertEqual(selfItem.summary?.contains("self post body"), true)
    }

    // MARK: - redditFields (pure)

    func testRedditFieldsLinkPostKeepsExternalDropsBody() throws {
        let feed = try FeedParser.parse(data: Data(redditAtom.utf8))
        let linkItem = try XCTUnwrap(feed.items.first { $0.title == "Great Article" })
        let fields = FeedRefresher.redditFields(for: linkItem, isReddit: true)
        XCTAssertEqual(fields.externalURL?.absoluteString, "https://blog.example.com/great-article")
        XCTAssertNil(fields.contentHTML, "link posts parse the external URL, so no body is stored")
    }

    func testRedditFieldsSelfPostKeepsBodyNoExternal() throws {
        let feed = try FeedParser.parse(data: Data(redditAtom.utf8))
        let selfItem = try XCTUnwrap(feed.items.first { $0.title == "A self post" })
        let fields = FeedRefresher.redditFields(for: selfItem, isReddit: true)
        XCTAssertNil(fields.externalURL)
        XCTAssertEqual(fields.contentHTML?.contains("self post body"), true)
    }

    func testRedditFieldsIgnoredForNonReddit() throws {
        let feed = try FeedParser.parse(data: Data(plainAtom.utf8))
        let item = try XCTUnwrap(feed.items.first)
        let fields = FeedRefresher.redditFields(for: item, isReddit: false)
        XCTAssertNil(fields.externalURL)
        XCTAssertNil(fields.contentHTML)
    }

    // MARK: - Domain-aware serialization decision

    func testPartitionSplitsRedditFromRest() {
        let urls = [
            URL(string: "https://www.reddit.com/r/swift/.rss")!,
            URL(string: "https://daringfireball.net/feeds/main")!,
            URL(string: "https://old.reddit.com/r/ios/.rss")!,
            URL(string: "https://example.com/feed.xml")!,
        ]
        let (concurrent, sequential) = RedditPolicy.partition(urls)
        XCTAssertEqual(concurrent.map(\.host), ["daringfireball.net", "example.com"])
        XCTAssertEqual(sequential.map(\.host), ["www.reddit.com", "old.reddit.com"])
    }

    func testPartitionAllConcurrentWhenNoReddit() {
        let urls = [URL(string: "https://a.com/f")!, URL(string: "https://b.com/f")!]
        let (concurrent, sequential) = RedditPolicy.partition(urls)
        XCTAssertEqual(concurrent.count, 2)
        XCTAssertTrue(sequential.isEmpty)
    }

    // MARK: - Narwhal deep link

    func testNarwhalDeepLink() throws {
        let permalink = URL(string: "https://www.reddit.com/r/swift/comments/aaa111/self_post/")!
        let narwhal = try XCTUnwrap(RedditFeed.narwhalURL(forPermalink: permalink))
        XCTAssertEqual(
            narwhal.absoluteString,
            "narwhal://open-url/https%3A%2F%2Fwww.reddit.com%2Fr%2Fswift%2Fcomments%2Faaa111%2Fself_post%2F"
        )
        XCTAssertEqual(narwhal.scheme, RedditFeed.narwhalScheme)
    }

    // MARK: - Merge writes reddit fields onto persisted entries

    @MainActor
    func testMergeSetsRedditFieldsOnEntries() throws {
        let schema = Schema([
            Article.self, Highlight.self, Tag.self,
            Feed.self, FeedEntry.self, AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let feed = Feed(feedURL: URL(string: "https://www.reddit.com/r/swift/.rss")!)
        context.insert(feed)

        let parsed = try FeedParser.parse(data: Data(redditAtom.utf8))
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try context.save()

        let byGuid = Dictionary(uniqueKeysWithValues: feed.allEntries.map { ($0.guid, $0) })

        let selfEntry = try XCTUnwrap(byGuid["t3_aaa111"])
        XCTAssertNil(selfEntry.externalURL)
        XCTAssertEqual(selfEntry.contentHTML?.contains("self post body"), true)

        let linkEntry = try XCTUnwrap(byGuid["t3_bbb222"])
        XCTAssertEqual(linkEntry.externalURL?.absoluteString, "https://blog.example.com/great-article")
        XCTAssertNil(linkEntry.contentHTML)
        // The comments permalink stays the entry URL in both cases.
        XCTAssertEqual(linkEntry.url?.absoluteString,
                       "https://www.reddit.com/r/swift/comments/bbb222/great_article/")
    }

    // MARK: - Discussion opener resolution

    @MainActor
    func testDiscussionOpenerResolution() {
        let permalink = URL(string: "https://www.reddit.com/r/swift/comments/aaa111/self_post/")!

        if case .openExternally(let url) = DiscussionOpener.resolve(permalink: permalink, preference: .systemDefault) {
            XCTAssertEqual(url, permalink)
        } else {
            XCTFail("systemDefault should open the reddit URL externally")
        }

        if case .presentInApp(let url) = DiscussionOpener.resolve(permalink: permalink, preference: .inApp) {
            XCTAssertEqual(url, permalink)
        } else {
            XCTFail("inApp should present the reddit URL in-app")
        }

        // Narwhal isn't installed in the test host, so it must fall back to the
        // reddit.com permalink (never silently fail to open anything).
        if case .openExternally(let url) = DiscussionOpener.resolve(permalink: permalink, preference: .narwhal) {
            XCTAssertEqual(url, permalink)
        } else {
            XCTFail("narwhal should fall back to opening the reddit URL externally")
        }
    }

    @MainActor
    func testMergeLeavesNonRedditEntriesUnchanged() throws {
        let schema = Schema([
            Article.self, Highlight.self, Tag.self,
            Feed.self, FeedEntry.self, AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let feed = Feed(feedURL: URL(string: "https://plain.example/feed.xml")!)
        context.insert(feed)

        let parsed = try FeedParser.parse(data: Data(plainAtom.utf8))
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try context.save()

        let entry = try XCTUnwrap(feed.allEntries.first)
        XCTAssertNil(entry.externalURL)
        XCTAssertNil(entry.contentHTML)
        XCTAssertEqual(entry.url?.absoluteString, "https://plain.example/one")
    }
}
