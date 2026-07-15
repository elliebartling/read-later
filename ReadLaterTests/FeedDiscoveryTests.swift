import XCTest
@testable import ReadLater

final class FeedDiscoveryTests: XCTestCase {

    private let base = URL(string: "https://example.com/blog/post")!

    // MARK: - <link> extraction

    func testFindsDoubleQuotedFeedLink() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="Main" href="/feed.xml">
        </head></html>
        """
        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: base)
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url.absoluteString, "https://example.com/feed.xml")
        XCTAssertEqual(feeds[0].title, "Main")
    }

    func testFindsSingleQuotedAtomLinkCaseInsensitively() {
        let html = "<LINK REL='alternate' TYPE='Application/Atom+XML' HREF='https://other.com/atom.xml'/>"
        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: base)
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url.absoluteString, "https://other.com/atom.xml")
    }

    func testIgnoresStylesheetAndNonFeedLinks() {
        let html = """
        <link rel="stylesheet" href="/style.css">
        <link rel="alternate" type="text/html" hreflang="fr" href="/fr">
        <link rel="icon" href="/favicon.ico">
        """
        XCTAssertTrue(FeedDiscovery.feedLinks(inHTML: html, baseURL: base).isEmpty)
    }

    func testDeduplicatesRepeatedHrefsAndPreservesOrder() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="/a.xml">
        <link rel="alternate" type="application/rss+xml" href="/b.xml">
        <link rel="alternate" type="application/atom+xml" href="/a.xml">
        """
        let feeds = FeedDiscovery.feedLinks(inHTML: html, baseURL: base)
        XCTAssertEqual(feeds.map(\.url.lastPathComponent), ["a.xml", "b.xml"])
    }

    func testRelHandlesMultipleTokens() {
        let html = "<link rel=\"alternate feed\" type=\"application/rss+xml\" href=\"/rss\">"
        XCTAssertEqual(FeedDiscovery.feedLinks(inHTML: html, baseURL: base).count, 1)
    }

    // MARK: - Feed sniffing

    func testRecognizesRSSDocument() {
        let xml = "<?xml version=\"1.0\"?>\n<rss version=\"2.0\"><channel></channel></rss>"
        XCTAssertTrue(FeedDiscovery.isLikelyFeedDocument(Data(xml.utf8)))
    }

    func testRecognizesAtomDocument() {
        let xml = "<?xml version=\"1.0\"?><feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>"
        XCTAssertTrue(FeedDiscovery.isLikelyFeedDocument(Data(xml.utf8)))
    }

    func testRejectsHTMLDocumentMentioningRSS() {
        let html = "<!doctype html><html><body><p>Subscribe to our <rss> page</p></body></html>"
        XCTAssertFalse(FeedDiscovery.isLikelyFeedDocument(Data(html.utf8)))
    }

    func testRejectsPlainText() {
        XCTAssertFalse(FeedDiscovery.isLikelyFeedDocument(Data("just words".utf8)))
    }

    // MARK: - Common paths

    func testCommonFeedPathsProbeSiteRoot() {
        let deep = URL(string: "https://example.com/blog/2026/07/post?utm=x#frag")!
        let paths = FeedDiscovery.commonFeedPaths(for: deep)
        XCTAssertTrue(paths.contains(URL(string: "https://example.com/feed")!))
        XCTAssertTrue(paths.contains(URL(string: "https://example.com/index.xml")!))
        XCTAssertTrue(paths.allSatisfy { $0.host == "example.com" })
        XCTAssertTrue(paths.allSatisfy { $0.query == nil && $0.fragment == nil })
    }
}
