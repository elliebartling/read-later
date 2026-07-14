import XCTest
@testable import ReadLater

final class FeedParserTests: XCTestCase {

    // MARK: - RSS 2.0

    private let rss2Sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" \
    xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>Example Blog &amp; Notes</title>
        <link>https://example.com/</link>
        <description>A blog.</description>
        <image>
          <url>https://example.com/logo.png</url>
          <title>Logo title should not win</title>
          <link>https://example.com/</link>
        </image>
        <item>
          <title>First Post</title>
          <link>https://example.com/posts/1</link>
          <guid isPermaLink="false">post-1</guid>
          <pubDate>Mon, 06 Jul 2026 10:30:00 +0000</pubDate>
          <dc:creator>Jane Writer</dc:creator>
          <description><![CDATA[<p>Hello <b>world</b> &amp; friends.</p>]]></description>
        </item>
        <item>
          <title>Second Post</title>
          <link>https://example.com/posts/2</link>
          <pubDate>Tue, 07 Jul 2026 08:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    func testParsesRSS2Channel() throws {
        let feed = try FeedParser.parse(data: Data(rss2Sample.utf8))
        XCTAssertEqual(feed.title, "Example Blog & Notes")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://example.com/")
        XCTAssertEqual(feed.items.count, 2)
    }

    func testParsesRSS2Item() throws {
        let feed = try FeedParser.parse(data: Data(rss2Sample.utf8))
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.title, "First Post")
        XCTAssertEqual(item.url?.absoluteString, "https://example.com/posts/1")
        XCTAssertEqual(item.guid, "post-1")
        XCTAssertEqual(item.author, "Jane Writer")
        XCTAssertEqual(item.summary, "Hello world & friends.")
        let published = try XCTUnwrap(item.publishedAt)
        // Mon, 06 Jul 2026 10:30:00 +0000
        XCTAssertEqual(published.timeIntervalSince1970, 1_783_333_800, accuracy: 1)
    }

    func testGuidFallsBackToItemURL() throws {
        let feed = try FeedParser.parse(data: Data(rss2Sample.utf8))
        XCTAssertEqual(feed.items[1].guid, "https://example.com/posts/2")
    }

    func testRSSNamedTimeZoneDateParses() throws {
        let feed = try FeedParser.parse(data: Data(rss2Sample.utf8))
        XCTAssertNotNil(feed.items[1].publishedAt)
    }

    // MARK: - Atom

    private let atomSample = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Example</title>
      <link rel="self" href="https://example.org/feed.xml"/>
      <link rel="alternate" type="text/html" href="https://example.org/"/>
      <updated>2026-07-05T12:00:00Z</updated>
      <entry>
        <title>Entry One</title>
        <link rel="alternate" href="https://example.org/one"/>
        <id>tag:example.org,2026:one</id>
        <published>2026-07-05T09:15:30Z</published>
        <updated>2026-07-06T10:00:00Z</updated>
        <summary type="html">&lt;p&gt;Summary &amp;amp; more&lt;/p&gt;</summary>
        <author><name>Ada Author</name></author>
      </entry>
    </feed>
    """

    func testParsesAtomFeed() throws {
        let feed = try FeedParser.parse(data: Data(atomSample.utf8))
        XCTAssertEqual(feed.title, "Atom Example")
        // rel="self" must not win over rel="alternate"
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://example.org/")
        XCTAssertEqual(feed.items.count, 1)
    }

    func testParsesAtomEntry() throws {
        let feed = try FeedParser.parse(data: Data(atomSample.utf8))
        let entry = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(entry.title, "Entry One")
        XCTAssertEqual(entry.url?.absoluteString, "https://example.org/one")
        XCTAssertEqual(entry.guid, "tag:example.org,2026:one")
        XCTAssertEqual(entry.author, "Ada Author")
        XCTAssertEqual(entry.summary, "Summary & more")
        let published = try XCTUnwrap(entry.publishedAt)
        // <published>, not the later <updated>
        XCTAssertEqual(published.timeIntervalSince1970, 1_783_242_930, accuracy: 1)
    }

    // MARK: - RDF (RSS 1.0)

    private let rdfSample = """
    <?xml version="1.0"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" \
    xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://example.net/">
        <title>RDF Example</title>
        <link>https://example.net/</link>
      </channel>
      <item rdf:about="https://example.net/item">
        <title>RDF Item</title>
        <link>https://example.net/item</link>
        <dc:date>2026-07-04T08:00:00+02:00</dc:date>
      </item>
    </rdf:RDF>
    """

    func testParsesRDFFeed() throws {
        let feed = try FeedParser.parse(data: Data(rdfSample.utf8))
        XCTAssertEqual(feed.title, "RDF Example")
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].title, "RDF Item")
        XCTAssertNotNil(feed.items[0].publishedAt)
    }

    // MARK: - Rejection

    func testRejectsHTMLDocument() {
        let html = "<html><head><title>Nope</title></head><body></body></html>"
        XCTAssertThrowsError(try FeedParser.parse(data: Data(html.utf8)))
    }

    // MARK: - Date parsing

    func testParsesRFC822Dates() {
        XCTAssertNotNil(FeedParser.parseDate("Mon, 06 Jul 2026 10:30:00 +0000"))
        XCTAssertNotNil(FeedParser.parseDate("Tue, 07 Jul 2026 08:00:00 GMT"))
        XCTAssertNotNil(FeedParser.parseDate("Tue, 07 Jul 2026 08:00 EST"))
    }

    func testParsesISO8601Dates() {
        XCTAssertNotNil(FeedParser.parseDate("2026-07-05T09:15:30Z"))
        XCTAssertNotNil(FeedParser.parseDate("2026-07-05T09:15:30.123Z"))
        XCTAssertNotNil(FeedParser.parseDate("2026-07-04T08:00:00+02:00"))
        XCTAssertNotNil(FeedParser.parseDate("2026-07-04"))
    }

    func testUnparseableDateReturnsNil() {
        XCTAssertNil(FeedParser.parseDate("yesterday-ish"))
        XCTAssertNil(FeedParser.parseDate(""))
    }

    // MARK: - Summary cleanup

    func testPlainSummaryStripsTagsAndEntities() {
        let html = "<p>A &quot;quoted&quot; <a href=\"x\">link</a>&nbsp;&amp;&#8217;s tail</p>"
        XCTAssertEqual(FeedParser.plainSummary(html), "A \"quoted\" link &\u{2019}s tail")
    }

    func testPlainSummaryCollapsesWhitespaceAndCapsLength() throws {
        let long = String(repeating: "word ", count: 200)
        let summary = try XCTUnwrap(FeedParser.plainSummary("<div>\n \(long)\n</div>"))
        XCTAssertLessThanOrEqual(summary.count, 400)
        XCTAssertFalse(summary.contains("\n"))
    }

    func testPlainSummaryReturnsNilForTagOnlyInput() {
        XCTAssertNil(FeedParser.plainSummary("<p> \n </p>"))
    }

    func testDecodeNumericEntities() {
        XCTAssertEqual(FeedParser.decodeEntities("&#65;&#x42;"), "AB")
    }
}
