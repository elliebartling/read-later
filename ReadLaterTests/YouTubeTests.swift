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

    // MARK: - Failure recovery (build 34 device bug: feed video → "couldn't parse")

    /// The exact watch-URL shape a real `feeds/videos.xml` entry carries
    /// (`<link rel="alternate" href="https://www.youtube.com/watch?v=<id>">`).
    /// Video IDs beginning with `_`/`-` are common and must survive routing.
    private static let realFeedWatchURL = URL(string: "https://www.youtube.com/watch?v=_oRgdlJUD18")!

    /// A YouTube watch page routinely cancels its first provisional navigation
    /// (consent interstitial, `?app=desktop`, m↔www redirect) and supersedes it
    /// with another. Treating that `NSURLErrorCancelled` as a fatal load failure
    /// aborted the parse before `didFinish`, dropping a *reachable* video into
    /// `.failed` — which renders the generic "couldn't parse www.youtube.com"
    /// screen. Only genuine load failures (offline) are fatal.
    func testCancelledNavigationIsNotFatalButOfflineIs() {
        XCTAssertTrue(YouTubeURL.isVideoURL(Self.realFeedWatchURL),
                      "the real videos.xml watch URL must route to the video parser")
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertFalse(VideoArticleParser.isFatalNavigationError(cancelled))
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertTrue(VideoArticleParser.isFatalNavigationError(offline))
        let noHost = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        XCTAssertTrue(VideoArticleParser.isFatalNavigationError(noHost))
    }

    /// Once a video's first parse lands `.failed`, reopening its feed entry must
    /// re-parse through the router (so it re-routes to the video parser and its
    /// metadata fallback) rather than silently reopening the failed article —
    /// which trapped the entry on the "couldn't parse" screen with no way out.
    func testFailedArticleIsNotReusedOnReopen() {
        let failed = Article(url: Self.realFeedWatchURL, title: "iOS 27 Hands-On", parseStatus: .failed)
        XCTAssertFalse(FeedEntriesView.shouldReuseExisting(failed),
                       "a failed article must re-parse (re-route) on reopen")
        let ready = Article(url: Self.realFeedWatchURL, title: "iOS 27 Hands-On", parseStatus: .ready)
        XCTAssertTrue(FeedEntriesView.shouldReuseExisting(ready))
        let pending = Article(url: Self.realFeedWatchURL, title: "iOS 27 Hands-On", parseStatus: .pending)
        XCTAssertTrue(FeedEntriesView.shouldReuseExisting(pending))
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
        // Metadata card leads: thumbnail image block, title heading, byline.
        XCTAssertEqual(parsed.blocks.first?.type, .image)
        XCTAssertEqual(parsed.blocks.first?.src?.absoluteString, "https://i.ytimg.com/vi/aircAruvnKk/hqdefault.jpg")
        XCTAssertEqual(parsed.blocks[1].type, .heading)
        XCTAssertEqual(parsed.blocks[1].text, "But what is a neural network?")
        XCTAssertEqual(parsed.blocks[2].type, .caption)
        XCTAssertEqual(parsed.blocks[2].text, "3Blue1Brown · YouTube")
        // Body is transcript paragraphs.
        XCTAssertTrue(parsed.blocks.dropFirst(3).allSatisfy { $0.type == .paragraph })
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
        // image + heading + byline + 3 description lines
        XCTAssertEqual(parsed.blocks.count, 6)
        XCTAssertEqual(parsed.blocks[0].type, .image)
        XCTAssertEqual(parsed.blocks[1].text, "Some Talk")
        XCTAssertEqual(parsed.blocks[2].text, "TED · YouTube")
        XCTAssertEqual(parsed.blocks[3].text, "First paragraph.")
        XCTAssertTrue(parsed.plainText.contains("still second paragraph"))
        XCTAssertEqual(parsed.plainText, ArticleBlocks.derivePlainText(parsed.blocks))
    }

    func testBuildParsedEmptyEverythingStillProducesABody() {
        let parsed = VideoArticleParser.buildParsed(
            videoID: "aircAruvnKk", title: "Silent", author: nil, description: "", cues: []
        )
        // image + heading + note (no byline — author nil)
        XCTAssertEqual(parsed.blocks.count, 3)
        XCTAssertEqual(parsed.blocks.last?.text, "No transcript available for this video.")
        XCTAssertNil(parsed.author)
    }

    /// The device-save regression: a description whose tail is a link pile must
    /// keep its prose and shed the trailing links — never the header card.
    func testBuildParsedTrimsTrailingLinkPile() {
        let description = """
        Actual prose about the game and what happened in it.

        SUBSCRIBE: https://youtube.com/gothamchess
        Follow me on Twitter: https://twitter.com/gothamchess
        #chess #gothamchess
        """
        let parsed = VideoArticleParser.buildParsed(
            videoID: "bPAZjLF0OPM", title: "Please, Stop! Please!", author: "Gotham Clips",
            description: description, cues: []
        )
        XCTAssertEqual(parsed.blocks[0].type, .image)
        XCTAssertEqual(parsed.blocks[1].text, "Please, Stop! Please!")
        XCTAssertEqual(parsed.blocks[2].text, "Gotham Clips · YouTube")
        XCTAssertEqual(parsed.blocks[3].text, "Actual prose about the game and what happened in it.")
        XCTAssertEqual(parsed.blocks.count, 4)
        // Dropped lines are inspectable via removedBlocks (same seam the cruft
        // filter uses), not silently vanished.
        XCTAssertEqual(parsed.removedBlocks.count, 3)
        XCTAssertFalse(parsed.plainText.contains("SUBSCRIBE"))
        XCTAssertEqual(parsed.plainText, ArticleBlocks.derivePlainText(parsed.blocks))
    }

    func testDescriptionParagraphs() {
        XCTAssertEqual(VideoArticleParser.descriptionParagraphs("a\n\nb\n\nc"), ["a", "b", "c"])
        XCTAssertEqual(VideoArticleParser.descriptionParagraphs("line1\nline2"), ["line1", "line2"])
        XCTAssertTrue(VideoArticleParser.descriptionParagraphs("   \n  ").isEmpty)
        // One paragraph per LINE — footer links stay individually classifiable.
        XCTAssertEqual(
            VideoArticleParser.descriptionParagraphs("prose\nhttps://a.example\n#tag"),
            ["prose", "https://a.example", "#tag"]
        )
    }

    // MARK: - Show-transcript UI drive: segment innerText parsing

    /// Fixtures captured live from the mid-2026 `transcript-segment-view-model`
    /// DOM: "<timestamp>\n[<a11y duration>\n]<cue>". The duration line is absent
    /// when its div is empty (first segment), and the whole panel is rendered
    /// TWICE in the DOM, so the raw list arrives with every segment duplicated.
    func testCuesFromSegmentInnerTexts() {
        let raw = [
            "0:00\nno Rosen is playing",
            "0:05\n5 seconds\nwhat wait am I am I Rosen is completely winning what Rosen just beat a",
            "0:14\n14 seconds\n3120 yeah they just had like an equal game",
            "12:14\n12 minutes, 14 seconds\n(Applause)",
            // duplicate copy of the whole panel (doubled DOM)
            "0:00\nno Rosen is playing",
            "0:05\n5 seconds\nwhat wait am I am I Rosen is completely winning what Rosen just beat a",
            "0:14\n14 seconds\n3120 yeah they just had like an equal game",
            "12:14\n12 minutes, 14 seconds\n(Applause)",
        ]
        let cues = VideoArticleParser.cues(fromSegmentInnerTexts: raw)
        XCTAssertEqual(cues, [
            "no Rosen is playing",
            "what wait am I am I Rosen is completely winning what Rosen just beat a",
            "3120 yeah they just had like an equal game",
            "(Applause)",
        ])
    }

    /// A legitimately repeated cue at a DIFFERENT timestamp must survive the
    /// dedupe (only the doubled-DOM copies collapse).
    func testSegmentDedupeKeepsRepeatedCuesAtDifferentTimes() {
        let raw = ["1:00\n1 minute\n[Music]", "2:00\n2 minutes\n[Music]", "1:00\n1 minute\n[Music]"]
        XCTAssertEqual(VideoArticleParser.cues(fromSegmentInnerTexts: raw), ["[Music]", "[Music]"])
    }

    func testTimestampAndDurationLineDetection() {
        XCTAssertTrue(VideoArticleParser.isTimestampLine("0:00"))
        XCTAssertTrue(VideoArticleParser.isTimestampLine("12:14"))
        XCTAssertTrue(VideoArticleParser.isTimestampLine("1:02:33"))
        XCTAssertFalse(VideoArticleParser.isTimestampLine("almost 12:14 exactly"))
        XCTAssertTrue(VideoArticleParser.isDurationLabelLine("5 seconds"))
        XCTAssertTrue(VideoArticleParser.isDurationLabelLine("1 minute, 5 seconds"))
        XCTAssertTrue(VideoArticleParser.isDurationLabelLine("1 hour, 2 minutes, 3 seconds"))
        XCTAssertFalse(VideoArticleParser.isDurationLabelLine("wait 5 seconds before moving"))
    }

    // MARK: - Trailing link-cruft trim (pure)

    func testIsLinkCruftLine() {
        XCTAssertTrue(VideoArticleParser.isLinkCruftLine("https://github.com/mnielsen/neural-networks"))
        XCTAssertTrue(VideoArticleParser.isLinkCruftLine("SUBSCRIBE: https://youtube.com/gothamchess"))
        XCTAssertTrue(VideoArticleParser.isLinkCruftLine("Follow me on Twitter: https://twitter.com/x"))
        XCTAssertTrue(VideoArticleParser.isLinkCruftLine("#chess #gothamchess #blitz"))
        XCTAssertTrue(VideoArticleParser.isLinkCruftLine("@gothamchess @chess"))
        // Prose that merely contains a link survives.
        XCTAssertFalse(VideoArticleParser.isLinkCruftLine(
            "I highly recommend the book by Michael Nielsen that introduces neural networks: https://goo.gl/Zmczdy"))
        XCTAssertFalse(VideoArticleParser.isLinkCruftLine("Actual prose about the game."))
    }

    func testTrimTrailingLinkCruftOnlyTrimsTail() {
        let paragraphs = [
            "Help fund future projects: https://www.patreon.com/3blue1brown", // link-ish but NOT trailing
            "There are two neat things about this book.",
            "https://github.com/mnielsen/neural-networks-and-deep-learning",
            "#math #neuralnetworks",
        ]
        let result = VideoArticleParser.trimTrailingLinkCruft(paragraphs)
        XCTAssertEqual(result.kept, Array(paragraphs.prefix(2)))
        XCTAssertEqual(result.removed, Array(paragraphs.suffix(2)))
    }

    func testTrimTrailingLinkCruftNeverNukesEverything() {
        let allLinks = ["https://a.example", "#tags only"]
        let result = VideoArticleParser.trimTrailingLinkCruft(allLinks)
        XCTAssertEqual(result.kept, allLinks)
        XCTAssertTrue(result.removed.isEmpty)
    }

    // MARK: - Adaptive load readiness (pure)

    func testLoadIsReady() {
        // Ready: target document, player response, interactive DOM.
        XCTAssertTrue(VideoArticleParser.loadIsReady(
            documentURL: "https://www.youtube.com/watch?v=aircAruvnKk",
            readyState: "interactive", hasPlayerResponse: true, videoID: "aircAruvnKk"))
        XCTAssertTrue(VideoArticleParser.loadIsReady(
            documentURL: "https://www.youtube.com/watch?v=aircAruvnKk&t=1s",
            readyState: "complete", hasPlayerResponse: true, videoID: "aircAruvnKk"))
        // Still the PREVIOUS document (stale player response) — not ready.
        XCTAssertFalse(VideoArticleParser.loadIsReady(
            documentURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            readyState: "complete", hasPlayerResponse: true, videoID: "aircAruvnKk"))
        // Player response not there yet.
        XCTAssertFalse(VideoArticleParser.loadIsReady(
            documentURL: "https://www.youtube.com/watch?v=aircAruvnKk",
            readyState: "complete", hasPlayerResponse: false, videoID: "aircAruvnKk"))
        // DOM still streaming in.
        XCTAssertFalse(VideoArticleParser.loadIsReady(
            documentURL: "https://www.youtube.com/watch?v=aircAruvnKk",
            readyState: "loading", hasPlayerResponse: true, videoID: "aircAruvnKk"))
        // No video id to verify against — never early-exit.
        XCTAssertFalse(VideoArticleParser.loadIsReady(
            documentURL: "https://www.youtube.com/watch?v=aircAruvnKk",
            readyState: "complete", hasPlayerResponse: true, videoID: ""))
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
