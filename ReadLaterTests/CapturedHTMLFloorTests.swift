import SwiftData
import XCTest
@testable import ReadLater

/// Covers the captured-content floor: the pure HTML-fragment walker that keeps a
/// Reddit self post out of `.failed` when we already hold its body, plus the
/// shared syndication-boilerplate trim it uses.
///
/// Fixtures are shaped from real `https://www.reddit.com/r/*/.rss` `<content>`
/// payloads (2026-08) as they arrive AFTER `XMLParser` decodes one entity level
/// — i.e. exactly what `FeedEntry.contentHTML` stores and what the reader hands
/// to `ArticleParser` as `prefetchedHTML`.
final class CapturedHTMLFloorTests: XCTestCase {

    private let url = URL(string: "https://www.reddit.com/r/AskHistorians/comments/abc/why/")!

    /// A short self post — the shape that failed. Readability's 500-character
    /// threshold rejects it, so the floor has to produce the blocks.
    private let shortSelfPost = """
    <!-- SC_OFF --><div class="md"><p>Why did Einstein reach a level of fame where his \
    name became synonymous with &quot;genius&quot;?</p> <p>My intuition is that most people \
    knew little about the underlying physics.</p></div><!-- SC_ON --> &#32; submitted by \
    &#32; <a href="https://www.reddit.com/user/asker"> /u/asker </a> <br/> \
    <span><a href="https://www.reddit.com/r/AskHistorians/comments/abc/why/">[link]</a></span> \
    &#32; <span><a href="https://www.reddit.com/r/AskHistorians/comments/abc/why/">[comments]</a></span>
    """

    // MARK: - Fragment → blocks

    func testShortSelfPostProducesParagraphBlocks() {
        let blocks = CapturedHTMLBlocks.blocks(fromCapturedHTML: shortSelfPost, baseURL: url)
        let paragraphs = blocks.compactMap { $0.type == .paragraph ? $0.text : nil }
        XCTAssertEqual(paragraphs.first, "Why did Einstein reach a level of fame where his name became synonymous with \"genius\"?")
        XCTAssertEqual(paragraphs.dropFirst().first, "My intuition is that most people knew little about the underlying physics.")
    }

    /// Reddit's `<!-- SC_OFF -->` / `<!-- SC_ON -->` markers must never reach text.
    func testCommentsAndScriptsAreDropped() {
        let blocks = CapturedHTMLBlocks.blocks(
            fromCapturedHTML: "<!-- SC_OFF --><div class=\"md\"><p>Body.</p></div>"
                + "<script>var x = '<p>nope</p>';</script><style>p { color: red }</style>",
            baseURL: url
        )
        let text = ArticleBlocks.derivePlainText(blocks)
        XCTAssertEqual(text, "Body.")
        XCTAssertFalse(text.contains("SC_OFF"))
        XCTAssertFalse(text.contains("nope"))
    }

    func testHeadingsListsQuotesAndCodeAreTyped() {
        let html = """
        <div class="md">
          <h2>Setup</h2>
          <ul><li>First item</li><li>Second item</li></ul>
          <ol start="3"><li>Third</li><li>Fourth</li></ol>
          <blockquote><p>Quoted line.</p></blockquote>
          <pre><code>swift build\nswift test</code></pre>
          <p>Closing prose.</p>
        </div>
        """
        let blocks = CapturedHTMLBlocks.blocks(fromCapturedHTML: html, baseURL: url)

        let heading = blocks.first { $0.type == .heading }
        XCTAssertEqual(heading?.text, "Setup")
        XCTAssertEqual(heading?.level, 2)

        let items = blocks.filter { $0.type == .listItem }
        XCTAssertEqual(items.map { $0.text }, [
            "\u{2022} First item", "\u{2022} Second item", "3. Third", "4. Fourth",
        ])
        XCTAssertTrue(items.allSatisfy { $0.markerBaked == true })
        XCTAssertEqual(items.first?.listStyle, .unordered)
        XCTAssertEqual(items.last?.listStyle, .ordered)

        XCTAssertTrue(blocks.contains { $0.isQuoted && $0.text == "Quoted line." })

        let code = blocks.first { $0.type == .preformatted }
        XCTAssertEqual(code?.text, "swift build\nswift test")

        XCTAssertTrue(blocks.contains { $0.type == .paragraph && $0.text == "Closing prose." })
    }

    func testImagesResolveAgainstBaseURLAndSkipTrackingPixels() {
        let html = """
        <div class="md"><p>Look:</p>
        <img src="/i/photo.png" alt="A photo" width="600" height="400">
        <img src="https://track.example/p.gif" width="1" height="1">
        <img src="data:image/gif;base64,AAAA">
        </div>
        """
        let images = CapturedHTMLBlocks.blocks(fromCapturedHTML: html, baseURL: url)
            .filter { $0.type == .image }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.src?.absoluteString, "https://www.reddit.com/i/photo.png")
        XCTAssertEqual(images.first?.alt, "A photo")
    }

    /// Markup the author typed (escaped in the source) is TEXT, not structure.
    func testEscapedMarkupStaysLiteralText() {
        let blocks = CapturedHTMLBlocks.blocks(
            fromCapturedHTML: "<div class=\"md\"><p>The result is &lt;p&gt;You clicked 0 times&lt;/p&gt;.</p></div>",
            baseURL: url
        )
        XCTAssertEqual(
            ArticleBlocks.derivePlainText(blocks),
            "The result is <p>You clicked 0 times</p>."
        )
    }

    // MARK: - Syndication boilerplate trim

    func testFooterBlockIsTrimmedFromCapturedBody() throws {
        let floor = try XCTUnwrap(CapturedHTMLBlocks.floorParsed(capturedHTML: shortSelfPost, url: url))
        XCTAssertFalse(floor.plainText.contains("submitted by"), "plainText: \(floor.plainText)")
        XCTAssertFalse(floor.plainText.contains("[comments]"))
        XCTAssertEqual(floor.removedBlocks.count, 1)
        XCTAssertTrue(floor.removedBlocks.first?.text?.contains("submitted by") ?? false)
    }

    func testStrippingTrailingBoilerplate() {
        XCTAssertEqual(
            CruftFilter.strippingTrailingBoilerplate(
                "Real prose here. submitted by /u/name [link] [comments]"
            ),
            "Real prose here."
        )
        XCTAssertEqual(
            CruftFilter.strippingTrailingBoilerplate("submitted by /u/name [link] [comments]"),
            ""
        )
        // Counter-fixtures: mid-text mentions and ordinary prose are untouched.
        XCTAssertEqual(
            CruftFilter.strippingTrailingBoilerplate("The form was submitted by /u/name and then reviewed."),
            "The form was submitted by /u/name and then reviewed."
        )
        XCTAssertEqual(
            CruftFilter.strippingTrailingBoilerplate("Nothing to strip."),
            "Nothing to strip."
        )
    }

    /// Safety valve: an item whose ONLY content is the footer keeps it rather
    /// than trimming to an empty article.
    func testFooterOnlyBodyIsNotTrimmedToEmpty() {
        let blocks = [ArticleBlock(type: .paragraph, text: "submitted by /u/name [link] [comments]")]
        let trimmed = CruftFilter.trimmingTrailingBoilerplate(blocks)
        XCTAssertEqual(trimmed.kept.count, 1)
        XCTAssertTrue(trimmed.removed.isEmpty)
    }

    // MARK: - Floor assembly

    func testFloorParsedKeepsTitleEmptySoTheSaveTitleSurvives() throws {
        let floor = try XCTUnwrap(CapturedHTMLBlocks.floorParsed(capturedHTML: shortSelfPost, url: url))
        XCTAssertEqual(floor.title, "", "the floor must never rename the article")
        XCTAssertFalse(floor.isPaywalledPartial)
        XCTAssertGreaterThanOrEqual(floor.estimatedReadingMinutes, 1)
    }

    /// plainText must be exactly the derived join of the kept blocks — it is the
    /// UTF-16 highlight offset space and the block reader's own view of the text.
    func testFloorPlainTextMatchesDerivedBlockText() throws {
        let floor = try XCTUnwrap(CapturedHTMLBlocks.floorParsed(capturedHTML: shortSelfPost, url: url))
        XCTAssertEqual(floor.plainText, ArticleBlocks.derivePlainText(floor.blocks))
        // And the block base offsets land on the block text, in UTF-16 units.
        let ns = floor.plainText as NSString
        let ranges = ArticleBlocks.textBlockRangesByIndex(floor.blocks)
        for (index, range) in ranges {
            XCTAssertEqual(ns.substring(with: range), floor.blocks[index].text)
        }
    }

    /// The floor is scoped to body FRAGMENTS. A captured whole page (what the
    /// Safari extension sends) must fall through to the real quality gate.
    func testFloorRejectsWholeCapturedPages() {
        XCTAssertTrue(CapturedHTMLBlocks.isBodyFragment("<div class=\"md\"><p>Body.</p></div>"))
        XCTAssertFalse(CapturedHTMLBlocks.isBodyFragment("<!doctype html><html><body><p>Page.</p></body></html>"))
        XCTAssertFalse(CapturedHTMLBlocks.isBodyFragment("<HTML><BODY><p>Page.</p></BODY></HTML>"))
        XCTAssertNil(CapturedHTMLBlocks.floorParsed(
            capturedHTML: "<html><body><p>A whole captured page.</p></body></html>", url: url
        ))
    }

    func testFloorReturnsNilForContentWithNoText() {
        XCTAssertNil(CapturedHTMLBlocks.floorParsed(capturedHTML: "", url: url))
        XCTAssertNil(CapturedHTMLBlocks.floorParsed(capturedHTML: "<div><p> </p></div>", url: url))
    }

    // MARK: - Re-parse recovers the captured body from the store

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Article.self, Highlight.self, Tag.self,
            Feed.self, FeedEntry.self, AppSettings.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    /// Reopening a Reddit self post that had landed `.failed` must re-parse its
    /// stored body, not its permalink (a JS shell that fails the same way).
    @MainActor
    func testReparseRecoversSelfPostBodyFromItsFeedEntry() throws {
        let context = try makeContext()
        let feed = Feed(feedURL: URL(string: "https://www.reddit.com/r/AskHistorians/.rss")!)
        context.insert(feed)
        let entry = FeedEntry(
            feed: feed, guid: "t3_abc", title: "Why Einstein?", url: url,
            contentHTML: shortSelfPost
        )
        context.insert(entry)
        let article = Article(url: url, title: "Why Einstein?", parseStatus: .failed)
        context.insert(article)
        try context.save()

        XCTAssertEqual(PendingSaveIngest.capturedHTML(for: article, context: context), shortSelfPost)
    }

    /// Counter-fixtures: a non-Reddit article, and a Reddit LINK post (whose
    /// entry keeps no body), both re-parse from the network as before.
    @MainActor
    func testReparseFindsNoCapturedBodyForLinkPostsOrOtherSites() throws {
        let context = try makeContext()
        let feed = Feed(feedURL: URL(string: "https://www.reddit.com/r/programming/.rss")!)
        context.insert(feed)
        let external = URL(string: "https://example.com/post")!
        context.insert(FeedEntry(
            feed: feed, guid: "t3_link", title: "A link", url: url, externalURL: external
        ))
        let linkArticle = Article(url: external, title: "A link")
        context.insert(linkArticle)
        let blogArticle = Article(url: URL(string: "https://overreacted.io/a-guide/")!, title: "A guide")
        context.insert(blogArticle)
        try context.save()

        XCTAssertNil(PendingSaveIngest.capturedHTML(for: linkArticle, context: context))
        XCTAssertNil(PendingSaveIngest.capturedHTML(for: blogArticle, context: context))
    }
}
