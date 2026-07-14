import XCTest
@testable import ReadLater

/// Covers the parse-fidelity fixes:
/// - preformatted coalescing (Medium's per-line `<pre>` / code-only `<p>`),
/// - the content quality gate that rejects nav shells,
/// - the DOM-stabilization sampling decision.
///
/// All three surfaces are pure (no WKWebView / main-actor state), so they run
/// as fast logic tests. The JS-side classification that turns a code-only `<p>`
/// into a `preformatted` block is exercised end-to-end in
/// `ArticleParserWebViewTests`.
final class ArticleParserFidelityTests: XCTestCase {

    private let base = URL(string: "https://example.com/post")!

    // MARK: - Preformatted coalescing

    func testConsecutivePreformattedLinesCoalesceWithNewlines() {
        // Medium emits a multi-line command as per-line preformatted siblings.
        let blocks: [ArticleBlock] = [
            ArticleBlock(type: .paragraph, text: "Install it:"),
            ArticleBlock(type: .preformatted, text: "brew tap example/tap"),
            ArticleBlock(type: .preformatted, text: "brew install example"),
            ArticleBlock(type: .preformatted, text: "claude mcp add-json '{\"a\":1}'"),
            ArticleBlock(type: .paragraph, text: "Done."),
        ]
        let out = ArticleParser.coalescePreformatted(blocks)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0].type, .paragraph)
        XCTAssertEqual(out[1].type, .preformatted)
        XCTAssertEqual(
            out[1].text,
            "brew tap example/tap\nbrew install example\nclaude mcp add-json '{\"a\":1}'"
        )
        XCTAssertEqual(out[2].type, .paragraph)
        XCTAssertEqual(out[2].text, "Done.")
    }

    func testSinglePreformattedBlockIsUnchanged() {
        // A lone <pre> — including an already-internally-multi-line one — must be
        // returned untouched (same id and text), never rewrapped.
        let pre = ArticleBlock(type: .preformatted, text: "let x = 1\n  let y = 2")
        let blocks: [ArticleBlock] = [
            ArticleBlock(type: .paragraph, text: "A snippet:"),
            pre,
            ArticleBlock(type: .paragraph, text: "After."),
        ]
        let out = ArticleParser.coalescePreformatted(blocks)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[1], pre) // identical block, id preserved
    }

    func testNonAdjacentPreformattedBlocksStaySeparate() {
        // A paragraph between two code blocks breaks the run.
        let blocks: [ArticleBlock] = [
            ArticleBlock(type: .preformatted, text: "a = 1"),
            ArticleBlock(type: .paragraph, text: "then"),
            ArticleBlock(type: .preformatted, text: "b = 2"),
        ]
        let out = ArticleParser.coalescePreformatted(blocks)
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0].text, "a = 1")
        XCTAssertEqual(out[2].text, "b = 2")
    }

    func testCoalescingLeavesNonPreformattedRunsAlone() {
        let blocks: [ArticleBlock] = [
            ArticleBlock(type: .heading, text: "H", level: 2),
            ArticleBlock(type: .paragraph, text: "one"),
            ArticleBlock(type: .paragraph, text: "two"),
        ]
        XCTAssertEqual(ArticleParser.coalescePreformatted(blocks), blocks)
    }

    /// End-to-end through the pure JS→typed mapping: a run of `preformatted`
    /// dicts (what the JS walk emits for per-line `<pre>` and code-only `<p>`)
    /// collapses into one block, and `derivePlainText` then joins its lines with
    /// "\n" — so the highlight offset space matches the rendered code block.
    func testBlocksFromJSCoalescesPreformattedRun() {
        let raw: [[String: Any]] = [
            ["type": "paragraph", "text": "Run:"],
            ["type": "preformatted", "text": "line one"],
            ["type": "preformatted", "text": "line two"],
            ["type": "paragraph", "text": "Fin."],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.map(\.type), [.paragraph, .preformatted, .paragraph])
        XCTAssertEqual(blocks[1].text, "line one\nline two")
        XCTAssertEqual(
            ArticleBlocks.derivePlainText(blocks),
            "Run:\n\nline one\nline two\n\nFin."
        )
    }

    // MARK: - Quality gate

    private func words(_ n: Int) -> String {
        (0 ..< n).map { "word\($0)" }.joined(separator: " ")
    }

    func testGateRejectsNavShell() {
        // The exact shell Ellen saw: four short link-like lines.
        let blocks: [ArticleBlock] = [
            ArticleBlock(type: .paragraph, text: "Sitemap"),
            ArticleBlock(type: .paragraph, text: "Sign in"),
            ArticleBlock(type: .paragraph, text: "Write"),
            ArticleBlock(type: .paragraph, text: "Search"),
        ]
        let text = ArticleBlocks.derivePlainText(blocks)
        XCTAssertFalse(ArticleParser.QualityGate.passes(plainText: text, blocks: blocks, linkDensity: 1.0))
    }

    func testGateRejectsShortHighLinkDensityResult() {
        let text = words(120) // above word floor, but...
        let blocks = [ArticleBlock(type: .paragraph, text: text)]
        // ...80% of it is anchor text and it's a short result: chrome.
        XCTAssertFalse(ArticleParser.QualityGate.passes(plainText: text, blocks: blocks, linkDensity: 0.8))
    }

    func testGateRejectsNearEmptyResult() {
        let blocks = [ArticleBlock(type: .paragraph, text: "Just a few words here")]
        XCTAssertFalse(ArticleParser.QualityGate.passes(plainText: "Just a few words here", blocks: blocks, linkDensity: 0.0))
    }

    func testGateAcceptsRealArticle() {
        let text = words(300)
        let blocks = [
            ArticleBlock(type: .heading, text: "Title", level: 1),
            ArticleBlock(type: .paragraph, text: words(150)),
            ArticleBlock(type: .paragraph, text: words(150)),
        ]
        XCTAssertTrue(ArticleParser.QualityGate.passes(plainText: text, blocks: blocks, linkDensity: 0.1))
    }

    func testGateAcceptsLongArticleEvenWithManyLinks() {
        // A link-heavy but genuinely long piece (e.g. a roundup) should pass —
        // the link-density veto only fires on short results.
        let text = words(600)
        let blocks = (0 ..< 12).map { ArticleBlock(type: .paragraph, text: words(50) + " item \($0)") }
        XCTAssertTrue(ArticleParser.QualityGate.passes(plainText: text, blocks: blocks, linkDensity: 0.55))
    }

    // MARK: - Stability tracker

    func testStabilityTrackerSettlesAfterTwoEqualSamples() {
        var t = ArticleParser.StabilityTracker(requiredStableSamples: 2)
        XCTAssertFalse(t.record(500)) // first sample of a run
        XCTAssertTrue(t.record(500))  // two equal in a row → settled
    }

    func testStabilityTrackerResetsWhenLengthChanges() {
        var t = ArticleParser.StabilityTracker(requiredStableSamples: 2)
        XCTAssertFalse(t.record(100)) // shell
        XCTAssertFalse(t.record(900)) // body streamed in → run resets
        XCTAssertTrue(t.record(900))  // now stable at the larger size
    }

    func testStabilityTrackerRequiresAtLeastOneSample() {
        var t = ArticleParser.StabilityTracker(requiredStableSamples: 1)
        XCTAssertTrue(t.record(42))
    }

    // MARK: - Full-render tracker (lazy-render scroll pump)

    func testFullRenderTrackerNotSettledWhileDocumentGrows() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        // Lazy page: every scroll pass appends content, so height/text keep moving.
        XCTAssertFalse(t.record(scrollHeight: 4000, textLength: 1000, atBottom: false))
        XCTAssertFalse(t.record(scrollHeight: 8000, textLength: 2100, atBottom: true))
        XCTAssertFalse(t.record(scrollHeight: 12000, textLength: 3400, atBottom: true))
    }

    func testFullRenderTrackerNotSettledUntilBottomReached() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        // The exact Medium trap: text length stabilizes (nothing new mounted)
        // but we haven't scrolled to the bottom yet — must NOT settle, or the
        // article truncates at the fold.
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, atBottom: false))
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, atBottom: false))
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, atBottom: false))
        // Bottom reached with metrics already stable → settled.
        XCTAssertTrue(t.record(scrollHeight: 9000, textLength: 5000, atBottom: true))
    }

    func testFullRenderTrackerSettlesAtBottomWithBothMetricsStable() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, atBottom: true))
        XCTAssertTrue(t.record(scrollHeight: 9000, textLength: 5000, atBottom: true))
    }

    func testFullRenderTrackerHeightGrowthAloneBlocksSettle() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        // Text quiet but layout still expanding (images/embeds sizing in):
        // height instability alone must hold the pump open.
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, atBottom: true))
        // Height moves: its stability run restarts even though text is stable.
        XCTAssertFalse(t.record(scrollHeight: 9600, textLength: 5000, atBottom: true))
        // Second consecutive sample at the new height completes the run.
        XCTAssertTrue(t.record(scrollHeight: 9600, textLength: 5000, atBottom: true))
    }
}
