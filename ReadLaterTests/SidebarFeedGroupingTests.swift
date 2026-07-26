import XCTest
@testable import ReadLater

/// The sidebar prototype groups subscriptions by source kind, derived purely
/// from the feed's URLs (no schema change). These pin that derivation.
final class SidebarFeedGroupingTests: XCTestCase {
    private func url(_ s: String) -> URL? { URL(string: s) }

    func testYouTubeChannelFeedIsYouTube() {
        let feed = url("https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123")
        XCTAssertEqual(FeedSourceKind.kind(feedURL: feed, siteURL: nil), .youtube)
    }

    func testRedditSubredditFeedIsReddit() {
        let feed = url("https://www.reddit.com/r/ios/.rss")
        XCTAssertEqual(FeedSourceKind.kind(feedURL: feed, siteURL: nil), .reddit)
    }

    func testOldRedditHostIsReddit() {
        let feed = url("https://old.reddit.com/r/swift/.rss")
        XCTAssertEqual(FeedSourceKind.kind(feedURL: feed, siteURL: nil), .reddit)
    }

    func testPlainBlogIsWeb() {
        let feed = url("https://daringfireball.net/feeds/main")
        XCTAssertEqual(FeedSourceKind.kind(feedURL: feed, siteURL: url("https://daringfireball.net/")), .web)
    }

    /// Some feeds only carry a site URL we recognise (e.g. a proxied feed
    /// document); the site URL is enough to classify.
    func testSiteURLClassifiesWhenFeedURLIsGeneric() {
        let feed = url("https://rsshub.example/youtube/user/foo")
        XCTAssertEqual(
            FeedSourceKind.kind(feedURL: feed, siteURL: url("https://www.youtube.com/@foo")),
            .youtube
        )
    }

    func testUnknownURLsFallBackToWeb() {
        XCTAssertEqual(FeedSourceKind.kind(feedURL: nil, siteURL: nil), .web)
    }

    func testDisplayOrderCoversEveryKind() {
        XCTAssertEqual(Set(FeedSourceKind.displayOrder), Set(FeedSourceKind.allCases))
    }
}
