import XCTest
@testable import ReadLater

/// Covers issue #75's media half: Reddit image / gallery / video posts, which
/// the wave-1 link/self split routed into the article extractor as raw asset
/// URLs (`https://i.redd.it/abc.jpeg`) and which therefore could only fail.
///
/// Fixtures are trimmed from **live** `https://www.reddit.com/r/*/.rss`
/// payloads captured 2026-08 (r/pics, r/oddlysatisfying, r/ClaudeCode), shaped
/// as they arrive AFTER `XMLParser` decodes one entity level — i.e. exactly
/// what `FeedEntry.contentHTML` stores. Note the surviving `&amp;` inside the
/// preview `src` query: that is real, and it is why the walker decodes
/// attributes a second time.
final class RedditMediaTests: XCTestCase {

    // MARK: - Fixtures (live captures)

    /// r/pics image post: preview thumbnail, `[link]` → the full-size asset.
    /// No self-text — the majority shape, and the one in Ellen's screenshot.
    private let imagePost = """
    <table> <tr><td> <a href="https://www.reddit.com/r/pics/comments/1vj4ylv/oc_my_mom/"> \
    <img src="https://preview.redd.it/qglppx6de7ih1.jpeg?width=640&amp;crop=smart&amp;auto=webp&amp;s=bbafb85" \
    alt="[OC] my mom lives on a curve where produce trucks flip sometimes. she cross stitched this." /> \
    </a> </td><td> &#32; submitted by &#32; <a href="https://www.reddit.com/user/ourseveres"> /u/ourseveres </a> \
    <br/> <span><a href="https://i.redd.it/qglppx6de7ih1.jpeg">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/pics/comments/1vj4ylv/oc_my_mom/">[comments]</a></span> \
    </td></tr></table>
    """

    /// r/ClaudeCode image post WITH self-text. The old routing threw this body
    /// away entirely: `redditFields` kept no `contentHTML` for a link post.
    private let imagePostWithSelfText = """
    <table> <tr><td> <a href="https://www.reddit.com/r/ClaudeCode/comments/1vj4oxh/akashic/"> \
    <img src="https://preview.redd.it/gtuv3gv8c7ih1.gif?width=640&amp;crop=smart&amp;s=a8cec3d" \
    alt="The Akashic Record for claude code!" /> </a> </td><td> <!-- SC_OFF --><div class="md">\
    <p>Maintains model coherence and fulfills the deterministic intent requirements.</p> \
    <p>Helios is the PreToolUse hook.</p></div><!-- SC_ON --> &#32; submitted by &#32; \
    <a href="https://www.reddit.com/user/dev"> /u/dev </a> <br/> \
    <span><a href="https://i.redd.it/gtuv3gv8c7ih1.gif">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/ClaudeCode/comments/1vj4oxh/akashic/">[comments]</a></span> \
    </td></tr></table>
    """

    /// r/oddlysatisfying video post: the still is an `external-preview` frame,
    /// and `[link]` is a bare `v.redd.it` id with no file extension — which is
    /// exactly why `v.redd.it` has to be recognised by HOST, not by extension.
    private let videoPost = """
    <table> <tr><td> <a href="https://www.reddit.com/r/oddlysatisfying/comments/1viy9mu/dandelion/"> \
    <img src="https://external-preview.redd.it/NjNzaTV5a3Qx.png?width=640&amp;crop=smart&amp;auto=webp&amp;s=5de3290" \
    alt="Dandelion fountain" /> </a> </td><td> &#32; submitted by &#32; \
    <a href="https://www.reddit.com/user/BreakfastTop6899"> /u/BreakfastTop6899 </a> <br/> \
    <span><a href="https://v.redd.it/eypzasmt16ih1">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/oddlysatisfying/comments/1viy9mu/dandelion/">[comments]</a></span> \
    </td></tr></table>
    """

    /// r/ClaudeCode gallery post: `[link]` → `reddit.com/gallery/<id>`, and the
    /// feed carries exactly ONE preview (a 140pt cover). The other images are
    /// unreachable without the Reddit API — see docs/reddit-media-posts.md.
    private let galleryPost = """
    <table> <tr><td> <a href="https://www.reddit.com/r/ClaudeCode/comments/1vj7n35/practical/"> \
    <img src="https://preview.redd.it/wa2fjqpky7ih1.png?width=140&amp;height=125&amp;auto=webp&amp;s=6df4a54" \
    alt="Practical Systems: A company that runs itself" /> </a> </td><td> <!-- SC_OFF -->\
    <div class="md"><p>The screenshots are Mission Control, the cockpit I built to watch it run.</p>\
    </div><!-- SC_ON --> &#32; submitted by &#32; <a href="https://www.reddit.com/user/founder"> /u/founder </a> \
    <br/> <span><a href="https://www.reddit.com/gallery/1vj7n35">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/ClaudeCode/comments/1vj7n35/practical/">[comments]</a></span> \
    </td></tr></table>
    """

    /// Self post — the counter-fixture. `[link]` == `[comments]`, so nothing
    /// here may be re-routed as media; it must keep taking the captured floor.
    private let selfPost = """
    <!-- SC_OFF --><div class="md"><p>Were there official limits on admission?</p></div>\
    <!-- SC_ON --> &#32; submitted by &#32; <a href="https://www.reddit.com/user/asker"> /u/asker </a> \
    <br/> <span><a href="https://www.reddit.com/r/AskHistorians/comments/xyz/limits/">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/AskHistorians/comments/xyz/limits/">[comments]</a></span>
    """

    /// External link post — the other counter-fixture. Must still be extracted
    /// as a real article, WebView and all.
    private let externalLinkPost = """
    <table> <tr><td> </td><td> &#32; submitted by &#32; \
    <a href="https://www.reddit.com/user/dev"> /u/dev </a> <br/> \
    <span><a href="https://github.com/anthropics/claude-code">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/ClaudeCode/comments/1vj0/tool/">[comments]</a></span> \
    </td></tr></table>
    """

    /// A crosspost of a TEXT post: `[link]` is another subreddit's permalink.
    /// Constructed (not captured) — crossposts are rare in a 25-item feed — but
    /// the shape is Reddit's standard table with a different `[link]` target.
    /// Reddit serves a JS app shell to an off-Reddit fetch, so extracting that
    /// permalink fails exactly like extracting our own does.
    private let crosspost = """
    <table> <tr><td> <a href="https://www.reddit.com/r/ClaudeCode/comments/1vk1/xpost/"> \
    <img src="https://preview.redd.it/xpostcover.png?width=140&amp;s=abc" alt="Crossposted" /> </a> \
    </td><td> &#32; submitted by &#32; <a href="https://www.reddit.com/user/sharer"> /u/sharer </a> <br/> \
    <span><a href="https://www.reddit.com/r/programming/comments/1va2/original/">[link]</a></span> &#32; \
    <span><a href="https://www.reddit.com/r/ClaudeCode/comments/1vk1/xpost/">[comments]</a></span> \
    </td></tr></table>
    """

    private let permalink = URL(string: "https://www.reddit.com/r/pics/comments/1vj4ylv/oc_my_mom/")!

    // MARK: - MediaLink: URL classification

    func testRedditAssetHostsClassify() {
        XCTAssertEqual(kind("https://i.redd.it/qglppx6de7ih1.jpeg"), .image)
        XCTAssertEqual(kind("https://i.redd.it/gtuv3gv8c7ih1.gif"), .image)
        XCTAssertEqual(kind("https://preview.redd.it/abc.png?width=640&crop=smart"), .image)
        XCTAssertEqual(kind("https://external-preview.redd.it/abc.png?width=640"), .image)
        // No extension at all — the host is the whole signal.
        XCTAssertEqual(kind("https://v.redd.it/eypzasmt16ih1"), .video)
        XCTAssertEqual(kind("https://www.reddit.com/gallery/1vj1cay"), .gallery)
    }

    func testGenericExtensionsClassify() {
        XCTAssertEqual(kind("https://example.com/photos/sunset.JPG"), .image)
        XCTAssertEqual(kind("https://i.imgur.com/abc123.png"), .image)
        XCTAssertEqual(kind("https://cdn.example.com/clip.mp4"), .video)
        XCTAssertEqual(kind("https://cdn.example.com/clip.webm"), .video)
    }

    /// A false positive here would replace a real article with a broken image,
    /// so the negative cases matter more than the positive ones.
    func testOrdinaryPagesAreNotMedia() {
        XCTAssertNil(kind("https://overreacted.io/before-you-memo/"))
        XCTAssertNil(kind("https://example.com/2020/01/post.html"))
        XCTAssertNil(kind("https://example.com/report.pdf"))
        // An imgur ALBUM is a page with prose and layout; only `i.imgur.com`
        // serves the bare file.
        XCTAssertNil(kind("https://imgur.com/a/xyz123"))
        // A Reddit comments permalink is not a gallery.
        XCTAssertNil(kind("https://www.reddit.com/r/pics/comments/1vj4ylv/oc_my_mom/"))
        // `/gallery` with no id is not a gallery either.
        XCTAssertNil(kind("https://www.reddit.com/gallery"))
    }

    private func kind(_ raw: String) -> MediaKind? {
        guard let url = URL(string: raw) else { return nil }
        return MediaLink.kind(for: url)
    }

    // MARK: - RedditFeed.postKind: the routing decision

    func testImageGalleryAndVideoPostsAreCapturedNotLinks() {
        XCTAssertEqual(
            RedditFeed.postKind(fromContentHTML: imagePost),
            .captured(URL(string: "https://i.redd.it/qglppx6de7ih1.jpeg")!)
        )
        XCTAssertEqual(
            RedditFeed.postKind(fromContentHTML: videoPost),
            .captured(URL(string: "https://v.redd.it/eypzasmt16ih1")!)
        )
        XCTAssertEqual(
            RedditFeed.postKind(fromContentHTML: galleryPost),
            .captured(URL(string: "https://www.reddit.com/gallery/1vj7n35")!)
        )
    }

    func testCrosspostOfATextPostIsCaptured() {
        XCTAssertEqual(
            RedditFeed.postKind(fromContentHTML: crosspost),
            .captured(URL(string: "https://www.reddit.com/r/programming/comments/1va2/original/")!)
        )
    }

    func testSelfAndExternalLinkPostsKeepTheirOldClassification() {
        XCTAssertEqual(RedditFeed.postKind(fromContentHTML: selfPost), .selfPost)
        XCTAssertEqual(RedditFeed.postKind(fromContentHTML: nil), .selfPost)
        XCTAssertEqual(
            RedditFeed.postKind(fromContentHTML: externalLinkPost),
            .link(URL(string: "https://github.com/anthropics/claude-code")!)
        )
    }

    // MARK: - FeedRefresher: what the entry stores

    /// The regression in one assertion: a media post must NOT store its asset
    /// as `externalURL` (that URL became the saved article and went to
    /// Readability), and it MUST keep its body (that body holds the preview
    /// and the self-text).
    func testMediaPostKeepsItsBodyAndSetsNoExternalURL() {
        let fields = FeedRefresher.redditFields(
            for: item(contentHTML: imagePostWithSelfText), isReddit: true
        )
        XCTAssertNil(fields.externalURL)
        XCTAssertEqual(fields.contentHTML, imagePostWithSelfText)
    }

    func testExternalLinkPostStillStoresItsDestination() {
        let fields = FeedRefresher.redditFields(
            for: item(contentHTML: externalLinkPost), isReddit: true
        )
        XCTAssertEqual(fields.externalURL?.absoluteString, "https://github.com/anthropics/claude-code")
        XCTAssertNil(fields.contentHTML)
    }

    func testNonRedditFeedsAreUntouched() {
        let fields = FeedRefresher.redditFields(
            for: item(contentHTML: imagePost), isReddit: false
        )
        XCTAssertNil(fields.externalURL)
        XCTAssertNil(fields.contentHTML)
    }

    private func item(contentHTML: String) -> ParsedFeedItem {
        ParsedFeedItem(
            title: "A post",
            url: permalink,
            guid: "t3_abc",
            author: "/u/someone",
            contentHTML: contentHTML
        )
    }

    // MARK: - MediaArticleParser: what the reader gets

    /// The fix, end to end for the commonest case: image in, image out — at
    /// FULL resolution, not the feed's `crop=smart` 640pt preview.
    func testImagePostRendersTheFullSizeAsset() throws {
        let parsed = try XCTUnwrap(
            MediaArticleParser.parsed(url: permalink, capturedHTML: imagePost)
        )
        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks.first?.type, .image)
        XCTAssertEqual(
            parsed.blocks.first?.src?.absoluteString,
            "https://i.redd.it/qglppx6de7ih1.jpeg"
        )
        XCTAssertEqual(parsed.mediaKind, .image)
        XCTAssertEqual(parsed.mediaURL?.absoluteString, "https://i.redd.it/qglppx6de7ih1.jpeg")
        // The picture IS the post: no text, and therefore no reading estimate.
        XCTAssertEqual(parsed.plainText, "")
        XCTAssertEqual(parsed.estimatedReadingMinutes, 0)
        // Empty so the post keeps the title the save carried.
        XCTAssertEqual(parsed.title, "")
        // The library row gets the picture instead of a grey placeholder.
        XCTAssertEqual(parsed.heroImageURL?.absoluteString, "https://i.redd.it/qglppx6de7ih1.jpeg")
    }

    /// "submitted by /u/ourseveres [link] [comments]" must not become the
    /// caption of every picture on Reddit.
    func testSyndicationFooterNeverBecomesTheCaption() throws {
        let parsed = try XCTUnwrap(
            MediaArticleParser.parsed(url: permalink, capturedHTML: imagePost)
        )
        XCTAssertFalse(parsed.plainText.contains("submitted by"))
        XCTAssertFalse(parsed.plainText.contains("[link]"))
        XCTAssertEqual(parsed.removedBlocks.isEmpty, false)
    }

    func testImagePostKeepsItsSelfText() throws {
        let url = URL(string: "https://www.reddit.com/r/ClaudeCode/comments/1vj4oxh/akashic/")!
        let parsed = try XCTUnwrap(
            MediaArticleParser.parsed(url: url, capturedHTML: imagePostWithSelfText)
        )
        XCTAssertEqual(parsed.blocks.first?.type, .image)
        XCTAssertEqual(parsed.blocks.first?.src?.absoluteString, "https://i.redd.it/gtuv3gv8c7ih1.gif")
        let paragraphs = parsed.blocks.compactMap { $0.type == .paragraph ? $0.text : nil }
        XCTAssertEqual(paragraphs, [
            "Maintains model coherence and fulfills the deterministic intent requirements.",
            "Helios is the PreToolUse hook.",
        ])
        XCTAssertFalse(parsed.plainText.contains("submitted by"))
        XCTAssertEqual(parsed.estimatedReadingMinutes, 1)
    }

    /// The feed's own preview thumbnail must not appear a second time under
    /// the full-size asset.
    func testPreviewThumbnailIsNotDuplicated() throws {
        let parsed = try XCTUnwrap(
            MediaArticleParser.parsed(url: permalink, capturedHTML: imagePost)
        )
        let sources = parsed.blocks.compactMap { $0.src?.host }
        XCTAssertEqual(sources, ["i.redd.it"])
        XCTAssertFalse(sources.contains("preview.redd.it"))
    }

    func testVideoPostRendersItsPosterFrameAndCarriesThePlaybackURL() throws {
        let url = URL(string: "https://www.reddit.com/r/oddlysatisfying/comments/1viy9mu/dandelion/")!
        let parsed = try XCTUnwrap(MediaArticleParser.parsed(url: url, capturedHTML: videoPost))
        XCTAssertEqual(parsed.mediaKind, .video)
        XCTAssertEqual(parsed.mediaURL?.absoluteString, "https://v.redd.it/eypzasmt16ih1")
        // Poster frame, not the v.redd.it URL — that one is not an image.
        XCTAssertEqual(parsed.blocks.first?.type, .image)
        XCTAssertEqual(parsed.blocks.first?.src?.host, "external-preview.redd.it")
    }

    func testGalleryPostRendersItsCoverAndLinksOut() throws {
        let url = URL(string: "https://www.reddit.com/r/ClaudeCode/comments/1vj7n35/practical/")!
        let parsed = try XCTUnwrap(MediaArticleParser.parsed(url: url, capturedHTML: galleryPost))
        XCTAssertEqual(parsed.mediaKind, .gallery)
        XCTAssertEqual(parsed.mediaURL?.absoluteString, "https://www.reddit.com/gallery/1vj7n35")
        XCTAssertEqual(parsed.blocks.first?.src?.host, "preview.redd.it")
        // The gallery's caption survives alongside the cover.
        XCTAssertTrue(parsed.plainText.contains("Mission Control"))
    }

    func testCrosspostRendersItsPreviewRatherThanChasingTheOriginal() throws {
        let url = URL(string: "https://www.reddit.com/r/ClaudeCode/comments/1vk1/xpost/")!
        let parsed = MediaArticleParser.parsed(url: url, capturedHTML: crosspost)
        // A crosspost of a TEXT post has no media, so the media parser declines
        // and the captured floor renders the preview + body instead.
        XCTAssertNil(parsed)
        let floor = try XCTUnwrap(
            CapturedHTMLBlocks.floorParsed(capturedHTML: crosspost, url: url)
        )
        XCTAssertEqual(floor.blocks.map { $0.type }, [.image])
        XCTAssertEqual(floor.blocks.first?.src?.host, "preview.redd.it")
        // No text survives the footer trim, and that is fine: a picture with no
        // caption is still an article.
        XCTAssertEqual(floor.plainText, "")
        XCTAssertEqual(floor.estimatedReadingMinutes, 0)
    }

    /// The heal path for articles Ellen's build already spoiled: their URL IS
    /// the asset, and no captured body survives (the `PendingSave` that carried
    /// it was consumed at first ingest). Re-parsing must still produce a picture.
    func testDirectAssetURLWithNoCaptureStillRenders() throws {
        let asset = URL(string: "https://i.redd.it/qglppx6de7ih1.jpeg")!
        let parsed = try XCTUnwrap(MediaArticleParser.parsed(url: asset, capturedHTML: nil))
        XCTAssertEqual(parsed.blocks.map { $0.type }, [.image])
        XCTAssertEqual(parsed.blocks.first?.src, asset)
        XCTAssertEqual(parsed.mediaKind, .image)
    }

    // MARK: - MediaArticleParser: the declines

    func testSelfPostIsNotMedia() {
        XCTAssertNil(MediaArticleParser.parsed(url: permalink, capturedHTML: selfPost))
    }

    func testExternalLinkPostIsNotMedia() {
        XCTAssertNil(MediaArticleParser.parsed(url: permalink, capturedHTML: externalLinkPost))
    }

    func testOrdinaryArticleIsNotMedia() {
        let url = URL(string: "https://overreacted.io/before-you-memo/")!
        XCTAssertNil(MediaArticleParser.parsed(url: url, capturedHTML: nil))
    }

    /// A bare `v.redd.it` save with no feed entry behind it has no poster
    /// anywhere, and one unplayable link is worse than the failure state.
    func testBareVideoURLWithNoPosterDeclines() {
        let url = URL(string: "https://v.redd.it/eypzasmt16ih1")!
        XCTAssertNil(MediaArticleParser.parsed(url: url, capturedHTML: nil))
    }

    /// Scoping counter-fixture, same rule as the captured floor: the Safari
    /// extension sends `documentElement.outerHTML`. A whole page that merely
    /// *links* to an image is not a media post.
    func testWholePageCaptureIsNeverAMediaPost() {
        let page = """
        <html><head><title>Gallery roundup</title></head><body><nav>Home</nav>\
        <article><p>Prose.</p><span><a href="https://i.redd.it/abc.jpeg">[link]</a></span></article>\
        </body></html>
        """
        let url = URL(string: "https://example.com/roundup")!
        XCTAssertNil(MediaArticleParser.parsed(url: url, capturedHTML: page))
    }

    // MARK: - Latency: the short-fragment fast path

    /// A captured body under Readability's character threshold has a decided
    /// outcome before the WebView starts, so `parse` returns the floor directly.
    /// The contract this asserts is that the shortcut is **output-identical**
    /// to the slow path's ending — not merely faster.
    @MainActor
    func testShortFragmentParseMatchesTheFloorItSkipsTo() async throws {
        let url = URL(string: "https://www.reddit.com/r/AskHistorians/comments/xyz/limits/")!
        let floor = try XCTUnwrap(
            CapturedHTMLBlocks.floorParsed(capturedHTML: selfPost, url: url)
        )
        XCTAssertLessThan(floor.plainText.count, ArticleParser.readabilityCharThreshold)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: selfPost)
        XCTAssertEqual(parsed.plainText, floor.plainText)
        XCTAssertEqual(parsed.extractedHTML, floor.extractedHTML)
        XCTAssertEqual(parsed.blocks.map { $0.text }, floor.blocks.map { $0.text })
        XCTAssertEqual(parsed.title, "")
    }

    // MARK: - Article: the derived affordance

    func testPlaybackURLOnlyExistsWhereTheReaderCannotShowTheMedia() {
        let article = Article(url: permalink, title: "Post")
        article.mediaURL = URL(string: "https://i.redd.it/abc.jpeg")
        article.mediaKind = .image
        // The reader already shows (and zooms) the full image.
        XCTAssertNil(article.mediaPlaybackURL)

        article.mediaKind = .video
        article.mediaURL = URL(string: "https://v.redd.it/abc")
        XCTAssertEqual(article.mediaPlaybackURL?.absoluteString, "https://v.redd.it/abc")

        article.mediaKind = .gallery
        article.mediaURL = URL(string: "https://www.reddit.com/gallery/abc")
        XCTAssertEqual(article.mediaPlaybackURL?.absoluteString, "https://www.reddit.com/gallery/abc")
    }

    func testMediaKindRoundTripsThroughItsStoredString() {
        let article = Article(url: permalink, title: "Post")
        XCTAssertNil(article.mediaKind)
        for kind in MediaKind.allCases {
            article.mediaKind = kind
            XCTAssertEqual(article.mediaKindRaw, kind.rawValue)
            XCTAssertEqual(article.mediaKind, kind)
        }
        // A value written by a newer build reads as "an ordinary article",
        // never a decode failure.
        article.mediaKindRaw = "hologram"
        XCTAssertNil(article.mediaKind)
    }
}
