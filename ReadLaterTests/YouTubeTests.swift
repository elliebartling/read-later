import SwiftData
import XCTest
@testable import ReadLater

/// YouTube wave 1: URL routing/ID extraction, channel-reference classification
/// and channel-id scraping, transcript assembly from a captured json3 sample,
/// metadata fallback shaping, and the `media:thumbnail` feed path.
final class YouTubeTests: XCTestCase {

    // MARK: - Video URL detection / ID extraction

    func testVideoIDExtraction() {
        func id(_ s: String) -> String? { YouTubeURL.videoID(from: URL(string: s)) }
        XCTAssertEqual(id("https://www.youtube.com/watch?v=aircAruvnKk"), "aircAruvnKk")
        XCTAssertEqual(id("https://youtube.com/watch?v=aircAruvnKk&t=42s"), "aircAruvnKk")
        XCTAssertEqual(id("https://m.youtube.com/watch?v=aircAruvnKk"), "aircAruvnKk")
        XCTAssertEqual(id("https://music.youtube.com/watch?v=aircAruvnKk"), "aircAruvnKk")
        XCTAssertEqual(id("https://youtu.be/aircAruvnKk?si=trackingtoken"), "aircAruvnKk")
        XCTAssertEqual(id("https://www.youtube.com/shorts/aircAruvnKk"), "aircAruvnKk")
        XCTAssertEqual(id("https://www.youtube.com/embed/aircAruvnKk"), "aircAruvnKk")
        XCTAssertEqual(id("https://www.youtube.com/live/aircAruvnKk"), "aircAruvnKk")
    }

    func testNonVideoURLsReturnNil() {
        func id(_ s: String) -> String? { YouTubeURL.videoID(from: URL(string: s)) }
        XCTAssertNil(id("https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw"))
        XCTAssertNil(id("https://www.youtube.com/@3blue1brown"))
        XCTAssertNil(id("https://www.youtube.com/"))
        XCTAssertNil(id("https://www.youtube.com/watch?v=tooShort"))
        XCTAssertNil(id("https://example.com/watch?v=aircAruvnKk"))
        XCTAssertNil(YouTubeURL.videoID(from: nil))
    }

    func testRoutingPredicateAndLinkBuilders() {
        XCTAssertTrue(YouTubeURL.isVideoURL(URL(string: "https://youtu.be/aircAruvnKk")))
        XCTAssertFalse(YouTubeURL.isVideoURL(URL(string: "https://daringfireball.net/feeds/main")))
        XCTAssertEqual(YouTubeURL.watchURL(videoID: "aircAruvnKk")?.absoluteString,
                       "https://www.youtube.com/watch?v=aircAruvnKk")
        XCTAssertEqual(YouTubeURL.shareURL(videoID: "aircAruvnKk")?.absoluteString,
                       "https://youtu.be/aircAruvnKk")
        XCTAssertEqual(YouTubeURL.thumbnailURL(videoID: "aircAruvnKk")?.absoluteString,
                       "https://i.ytimg.com/vi/aircAruvnKk/hqdefault.jpg")
    }

    // MARK: - Channel reference classification

    func testChannelReferenceClassification() {
        // Direct channel id.
        XCTAssertEqual(
            YouTubeChannel.reference(from: "https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw"),
            .channelID("UCYO_jab_esuFRV4b17AJtAw")
        )
        // Handles / vanity URLs need resolution.
        for input in ["https://www.youtube.com/@3blue1brown", "youtube.com/@3blue1brown",
                      "@3blue1brown", "youtube.com/c/3blue1brown", "youtube.com/user/3blue1brown"] {
            guard case .needsResolution = YouTubeChannel.reference(from: input) else {
                return XCTFail("\(input) should need resolution")
            }
        }
        // Not channel references.
        XCTAssertNil(YouTubeChannel.reference(from: "https://www.youtube.com/watch?v=aircAruvnKk"))
        XCTAssertNil(YouTubeChannel.reference(from: "https://youtu.be/aircAruvnKk"))
        XCTAssertNil(YouTubeChannel.reference(from: "example.com"))
        XCTAssertNil(YouTubeChannel.reference(from: "r/swift"))
        XCTAssertNil(YouTubeChannel.reference(from: ""))
    }

    func testChannelIDFromHTML() {
        let id = "UCYO_jab_esuFRV4b17AJtAw"
        XCTAssertEqual(YouTubeChannel.channelID(fromHTML: "...\"channelId\":\"\(id)\",..."), id)
        XCTAssertEqual(YouTubeChannel.channelID(fromHTML: "<meta itemprop=\"channelId\" content=\"\(id)\">"), id)
        XCTAssertEqual(YouTubeChannel.channelID(fromHTML: "<link rel=\"canonical\" href=\"https://www.youtube.com/channel/\(id)\">"), id)
        XCTAssertNil(YouTubeChannel.channelID(fromHTML: "<html>no id here</html>"))
    }

    func testChannelFeedURL() {
        XCTAssertEqual(
            YouTubeChannel.feedURL(channelID: "UCYO_jab_esuFRV4b17AJtAw")?.absoluteString,
            "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw"
        )
    }

    // MARK: - Transcript assembly from a captured json3 sample

    /// Distilled real `json3` shape: events with `segs[].utf8`, a formatting-only
    /// `aAppend` event, and a trailing event with no `segs` (both skipped).
    private let json3Sample = """
    {"wireMagic":"pb3","events":[
      {"tStartMs":0,"dDurationMs":4000,"segs":[{"utf8":"Hello "},{"utf8":"and welcome"}]},
      {"tStartMs":10,"dDurationMs":0,"aAppend":1},
      {"tStartMs":4000,"dDurationMs":3000,"segs":[{"utf8":"to the   show"}]},
      {"tStartMs":7000,"dDurationMs":2000}
    ]}
    """

    func testCuesFromJSON3() {
        let cues = VideoArticleParser.cues(fromJSON3Text: json3Sample)
        XCTAssertEqual(cues, ["Hello and welcome", "to the show"])
        XCTAssertTrue(VideoArticleParser.cues(fromJSON3Text: "").isEmpty)
        XCTAssertTrue(VideoArticleParser.cues(fromJSON3Text: "<html>404</html>").isEmpty)
    }

    func testCoalesceCuesGroupsIntoParagraphs() {
        // 12 five-word cues = 60 words; at maxWords 20 that is 3 paragraphs.
        let cue = "one two three four five"
        let cues = Array(repeating: cue, count: 12)
        let paras = VideoArticleParser.coalesceCues(cues, maxWords: 20)
        XCTAssertEqual(paras.count, 3)
        // No text is lost and order is preserved.
        XCTAssertEqual(paras.joined(separator: " "), cues.joined(separator: " "))
    }

    func testBuildParsedWithTranscript() {
        let cues = VideoArticleParser.cues(fromJSON3Text: json3Sample)
        let parsed = VideoArticleParser.buildParsed(
            videoID: "aircAruvnKk",
            title: "But what is a neural network?",
            author: "3Blue1Brown",
            description: "ignored when a transcript exists",
            cues: cues
        )
        XCTAssertEqual(parsed.title, "But what is a neural network?")
        XCTAssertEqual(parsed.author, "3Blue1Brown")
        XCTAssertEqual(parsed.siteName, "YouTube")
        XCTAssertEqual(parsed.heroImageURL?.absoluteString, "https://i.ytimg.com/vi/aircAruvnKk/hqdefault.jpg")
        XCTAssertFalse(parsed.blocks.isEmpty)
        XCTAssertTrue(parsed.blocks.allSatisfy { $0.type == .paragraph })
        XCTAssertTrue(parsed.plainText.contains("Hello and welcome"))
        XCTAssertFalse(parsed.plainText.contains("ignored when"))
        // plainText is the UTF-16 highlight offset space — must equal the blocks
        // joined the canonical way.
        XCTAssertEqual(parsed.plainText, ArticleBlocks.derivePlainText(parsed.blocks))
    }

    func testBuildParsedMetadataFallbackUsesDescription() {
        let parsed = VideoArticleParser.buildParsed(
            videoID: "aircAruvnKk",
            title: "Some Talk",
            author: "TED",
            description: "First paragraph.\n\nSecond paragraph line one\nstill second paragraph.",
            cues: []
        )
        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertEqual(parsed.blocks.first?.text, "First paragraph.")
        XCTAssertTrue(parsed.plainText.contains("still second paragraph"))
        XCTAssertEqual(parsed.plainText, ArticleBlocks.derivePlainText(parsed.blocks))
    }

    func testBuildParsedEmptyEverythingStillProducesABlock() {
        let parsed = VideoArticleParser.buildParsed(
            videoID: "aircAruvnKk", title: "Silent", author: nil, description: "", cues: []
        )
        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks.first?.text, "No transcript available for this video.")
        XCTAssertNil(parsed.author)
    }

    func testDescriptionParagraphs() {
        XCTAssertEqual(VideoArticleParser.descriptionParagraphs("a\n\nb\n\nc"), ["a", "b", "c"])
        XCTAssertEqual(VideoArticleParser.descriptionParagraphs("line1\nline2"), ["line1", "line2"])
        XCTAssertTrue(VideoArticleParser.descriptionParagraphs("   \n  ").isEmpty)
    }

    // MARK: - YouTube channel Atom feed → thumbnail + video-URL entries

    /// Distilled `feeds/videos.xml?channel_id=…` Atom shape.
    private let channelAtom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
          xmlns:media="http://search.yahoo.com/mrss/"
          xmlns="http://www.w3.org/2005/Atom">
      <link rel="self" href="https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw"/>
      <id>yt:channel:UCYO_jab_esuFRV4b17AJtAw</id>
      <yt:channelId>UCYO_jab_esuFRV4b17AJtAw</yt:channelId>
      <title>3Blue1Brown</title>
      <link rel="alternate" href="https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw"/>
      <author><name>3Blue1Brown</name></author>
      <entry>
        <id>yt:video:aircAruvnKk</id>
        <yt:videoId>aircAruvnKk</yt:videoId>
        <title>But what is a neural network?</title>
        <link rel="alternate" href="https://www.youtube.com/watch?v=aircAruvnKk"/>
        <author><name>3Blue1Brown</name></author>
        <published>2026-07-10T12:00:00+00:00</published>
        <updated>2026-07-10T13:00:00+00:00</updated>
        <media:group>
          <media:title>But what is a neural network?</media:title>
          <media:thumbnail url="https://i2.ytimg.com/vi/aircAruvnKk/hqdefault.jpg" width="480" height="360"/>
          <media:description>A friendly intro to neural networks.</media:description>
        </media:group>
      </entry>
    </feed>
    """

    func testChannelFeedParsesThumbnailAndVideoURL() throws {
        let feed = try FeedParser.parse(data: Data(channelAtom.utf8))
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.title, "But what is a neural network?")
        XCTAssertEqual(item.url?.absoluteString, "https://www.youtube.com/watch?v=aircAruvnKk")
        XCTAssertEqual(item.thumbnailURL?.absoluteString, "https://i2.ytimg.com/vi/aircAruvnKk/hqdefault.jpg")
        // The entry URL routes to the video parser.
        XCTAssertTrue(YouTubeURL.isVideoURL(item.url))
    }

    @MainActor
    func testMergeWritesThumbnailOntoEntry() throws {
        let schema = Schema([
            Article.self, Highlight.self, Tag.self,
            Feed.self, FeedEntry.self, AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let feed = Feed(feedURL: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw")!)
        context.insert(feed)

        let parsed = try FeedParser.parse(data: Data(channelAtom.utf8))
        FeedRefresher.merge(parsed: parsed, into: feed, context: context)
        try context.save()

        let entry = try XCTUnwrap(feed.allEntries.first)
        XCTAssertEqual(entry.thumbnailURL?.absoluteString, "https://i2.ytimg.com/vi/aircAruvnKk/hqdefault.jpg")
        XCTAssertEqual(entry.url?.absoluteString, "https://www.youtube.com/watch?v=aircAruvnKk")
    }

    /// A non-media feed must not gain a thumbnail (additive-only guarantee).
    func testOrdinaryFeedHasNoThumbnail() throws {
        let plainRSS = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>Blog</title>
          <item><title>Post</title><link>https://blog.example/p1</link>
          <guid>https://blog.example/p1</guid></item>
        </channel></rss>
        """
        let feed = try FeedParser.parse(data: Data(plainRSS.utf8))
        XCTAssertNil(feed.items.first?.thumbnailURL)
    }
}
