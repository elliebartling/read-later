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
        XCTAssertFalse(t.record(scrollHeight: 4000, textLength: 1000, harvestTextLength: 900, atBottom: false))
        XCTAssertFalse(t.record(scrollHeight: 8000, textLength: 2100, harvestTextLength: 2000, atBottom: true))
        XCTAssertFalse(t.record(scrollHeight: 12000, textLength: 3400, harvestTextLength: 3300, atBottom: true))
    }

    func testFullRenderTrackerNotSettledUntilBottomReached() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        // The exact Medium trap: text length stabilizes (nothing new mounted)
        // but we haven't scrolled to the bottom yet — must NOT settle, or the
        // article truncates at the fold.
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: false))
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: false))
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: false))
        // Bottom reached with metrics already stable → settled.
        XCTAssertTrue(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: true))
    }

    func testFullRenderTrackerSettlesAtBottomWithBothMetricsStable() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: true))
        XCTAssertTrue(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: true))
    }

    func testFullRenderTrackerHeightGrowthAloneBlocksSettle() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        // Text quiet but layout still expanding (images/embeds sizing in):
        // height instability alone must hold the pump open.
        XCTAssertFalse(t.record(scrollHeight: 9000, textLength: 5000, harvestTextLength: 5000, atBottom: true))
        // Height moves: its stability run restarts even though text is stable.
        XCTAssertFalse(t.record(scrollHeight: 9600, textLength: 5000, harvestTextLength: 5000, atBottom: true))
        // Second consecutive sample at the new height completes the run.
        XCTAssertTrue(t.record(scrollHeight: 9600, textLength: 5000, harvestTextLength: 5000, atBottom: true))
    }

    func testFullRenderTrackerHarvestGrowthAloneBlocksSettle() {
        var t = ArticleParser.FullRenderTracker(requiredStableSamples: 2)
        // The virtualization trap: a renderer swapping equal-sized chunks keeps
        // height and visible text CONSTANT while the article is still streaming
        // through — only the monotonic banked-harvest length shows progress.
        // The pump must not settle while it grows.
        XCTAssertFalse(t.record(scrollHeight: 6000, textLength: 3000, harvestTextLength: 3000, atBottom: true))
        XCTAssertFalse(t.record(scrollHeight: 6000, textLength: 3000, harvestTextLength: 3800, atBottom: true))
        XCTAssertFalse(t.record(scrollHeight: 6000, textLength: 3000, harvestTextLength: 4600, atBottom: true))
        // Banked length stops moving: the second consecutive equal sample
        // completes its stability run and the pump may settle.
        XCTAssertTrue(t.record(scrollHeight: 6000, textLength: 3000, harvestTextLength: 4600, atBottom: true))
    }

    // MARK: - Pump deadline (adaptive cap)

    func testDeadlineAlwaysContinuesBeforeSoftCap() {
        var d = ArticleParser.PumpDeadline(soft: .seconds(20), hard: .seconds(60), growthGrace: .seconds(6))
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(1), progress: 0))
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(19), progress: 0)) // no growth needed yet
    }

    func testDeadlineStopsAtSoftCapWithoutRecentGrowth() {
        var d = ArticleParser.PumpDeadline(soft: .seconds(20), hard: .seconds(60), growthGrace: .seconds(6))
        _ = d.shouldContinue(elapsed: .seconds(2), progress: 3000) // growth early on
        // 18s of silence later, the soft cap arrives with stale growth: stop.
        XCTAssertFalse(d.shouldContinue(elapsed: .seconds(20), progress: 3000))
    }

    func testDeadlineExtendsPastSoftCapWhileGrowthContinues() {
        var d = ArticleParser.PumpDeadline(soft: .seconds(20), hard: .seconds(60), growthGrace: .seconds(6))
        // The long-article case that truncated on device: chunks are still
        // streaming in when the soft cap fires — pumping must continue.
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(19), progress: 10_000))
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(21), progress: 12_000))
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(30), progress: 20_000))
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(45), progress: 40_000))
        // Growth stops: the grace window drains and pumping ends.
        XCTAssertFalse(d.shouldContinue(elapsed: .seconds(52), progress: 40_000))
    }

    func testDeadlineHardCeilingWinsEvenWithGrowth() {
        var d = ArticleParser.PumpDeadline(soft: .seconds(20), hard: .seconds(60), growthGrace: .seconds(6))
        XCTAssertTrue(d.shouldContinue(elapsed: .seconds(59), progress: 100_000))
        // Still growing, but the ceiling is absolute — and the recent growth is
        // exactly what the truncation flag reports.
        XCTAssertFalse(d.shouldContinue(elapsed: .seconds(60), progress: 110_000))
        XCTAssertTrue(d.grewRecently(at: .seconds(60)))
    }

    func testDeadlineOscillationDoesNotCountAsGrowth() {
        var d = ArticleParser.PumpDeadline(soft: .seconds(20), hard: .seconds(60), growthGrace: .seconds(6))
        _ = d.shouldContinue(elapsed: .seconds(1), progress: 8000)
        // Virtualized churn: progress bobs below the high-water mark. None of
        // this is forward progress, so the soft cap must end the pump.
        _ = d.shouldContinue(elapsed: .seconds(10), progress: 7000)
        _ = d.shouldContinue(elapsed: .seconds(15), progress: 8020) // +20 < minGrowth
        XCTAssertFalse(d.shouldContinue(elapsed: .seconds(20), progress: 7900))
    }

    // MARK: - Assembly choice (snapshot vs harvested stream)

    private func paragraphs(_ count: Int, wordsEach: Int, prefix: String = "s") -> [ArticleBlock] {
        (0 ..< count).map { i in
            ArticleBlock(type: .paragraph, text: "\(prefix)\(i) " + words(wordsEach))
        }
    }

    func testAssemblyPrefersSnapshotWhenSimilar() {
        // Harvest inevitably carries a little in-article chrome (title heading,
        // byline); near-parity must NOT flip assembly away from the cleaner
        // Readability snapshot.
        let snapshot = paragraphs(10, wordsEach: 40)
        var harvested = [ArticleBlock(type: .heading, text: "Title chrome", level: 1)]
        harvested += snapshot
        let choice = ArticleParser.chooseAssembly(snapshot: snapshot, harvested: harvested)
        XCTAssertFalse(choice.usedHarvest)
        XCTAssertEqual(choice.blocks, snapshot)
    }

    func testAssemblyUsesHarvestWhenSnapshotIsTruncated() {
        // Virtualization / time-capped mount: the snapshot holds only the tail
        // of what the pump saw. The banked stream is the real article.
        let harvested = paragraphs(30, wordsEach: 40, prefix: "h")
        let snapshot = Array(harvested.suffix(8))
        let choice = ArticleParser.chooseAssembly(snapshot: snapshot, harvested: harvested)
        XCTAssertTrue(choice.usedHarvest)
        XCTAssertEqual(choice.blocks, harvested)
    }

    func testAssemblyEmptyHarvestFallsBackToSnapshot() {
        let snapshot = paragraphs(5, wordsEach: 30)
        let choice = ArticleParser.chooseAssembly(snapshot: snapshot, harvested: [])
        XCTAssertFalse(choice.usedHarvest)
        XCTAssertEqual(choice.blocks, snapshot)
    }

    func testAssemblyEmptySnapshotUsesHarvest() {
        // Readability found nothing on the final DOM (fully virtualized away)
        // but the pump banked the article as it streamed through.
        let harvested = paragraphs(12, wordsEach: 40, prefix: "h")
        let choice = ArticleParser.chooseAssembly(snapshot: [], harvested: harvested)
        XCTAssertTrue(choice.usedHarvest)
        XCTAssertEqual(choice.blocks, harvested)
    }

    func testAssemblyMarginBlocksFlappingOnSmallArticles() {
        // 15% longer but under the absolute margin: stay with the snapshot.
        let snapshot = [ArticleBlock(type: .paragraph, text: words(30))]
        let harvested = [
            ArticleBlock(type: .paragraph, text: words(30)),
            ArticleBlock(type: .paragraph, text: words(8)),
        ]
        let choice = ArticleParser.chooseAssembly(snapshot: snapshot, harvested: harvested)
        XCTAssertFalse(choice.usedHarvest)
    }
}
