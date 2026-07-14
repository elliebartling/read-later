import XCTest
@testable import ReadLater

/// Fixture-driven tests for the block-level cruft filter (Layer B of
/// docs/parser-cruft-design.md). Each removal fixture models the block
/// sequence Readability + the JS walker actually emit for a cruft pattern;
/// each counter-fixture proves legitimate content survives.
final class CruftFilterTests: XCTestCase {

    private func p(_ text: String) -> ArticleBlock { ArticleBlock(type: .paragraph, text: text) }
    private func h(_ text: String, _ level: Int = 2) -> ArticleBlock {
        ArticleBlock(type: .heading, text: text, level: level)
    }
    private func li(_ text: String) -> ArticleBlock {
        ArticleBlock(type: .listItem, text: text, listStyle: .unordered)
    }

    private func keptTexts(_ blocks: [ArticleBlock]) -> [String] {
        CruftFilter.filter(blocks).kept.compactMap(\.text)
    }

    // MARK: - Removal fixtures: Medium nags (Ellen's real examples)

    func testRemovesMediumInboxNag() {
        let blocks = [
            p("The actual article begins with a promising thought."),
            p("Get Jane Doe's stories in your inbox"),
            p("And continues with more real prose."),
        ]
        XCTAssertEqual(keptTexts(blocks), [
            "The actual article begins with a promising thought.",
            "And continues with more real prose.",
        ])
    }

    func testRemovesJoinMediumNag() {
        let blocks = [
            p("Real content."),
            p("Join Medium for free to get updates from this writer."),
            p("More real content."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Real content.", "More real content."])
    }

    func testRemovesRememberMeSignInNag() {
        let blocks = [
            p("Remember me for faster sign in"),
            p("The article itself."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["The article itself."])
    }

    func testRemovesMemberOnlyStoryBadge() {
        let blocks = [
            p("Member-only story"),
            h("A Great Title", 1),
            p("Body text."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["A Great Title", "Body text."])
    }

    // MARK: - Removal fixtures: newsletter / membership nags

    func testRemovesNewsletterSubscribePrompts() {
        let blocks = [
            p("Prose before."),
            p("Sign up for our newsletter to get the latest in your inbox."),
            p("Type your email…"),
            p("Prose after."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Prose before.", "Prose after."])
    }

    func testRemovesPaywallNags() {
        let blocks = [
            p("This post is for paid subscribers"),
            p("Already have an account? Sign in."),
            p("Actual writing."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Actual writing."])
    }

    // MARK: - Removal fixtures: auth CTAs (whole-block exact)

    func testRemovesExactAuthButtons() {
        let blocks = [
            p("Sign in"),
            p("Continue with Google"),
            p("Continue with Apple"),
            p("Forgot password?"),
            p("Genuine paragraph of article prose that talks about something."),
        ]
        XCTAssertEqual(keptTexts(blocks), [
            "Genuine paragraph of article prose that talks about something.",
        ])
    }

    // MARK: - Removal fixtures: "N min read" metadata

    func testRemovesMinReadMetadata() {
        let blocks = [
            p("6 min read"),
            p("12 minute read"),
            p("4 min listen"),
            p("Body."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Body."])
    }

    func testRemovesFreeStoriesCounterAndFollowers() {
        let blocks = [
            p("2 free stories left"),
            p("1.2K Followers"),
            p("Body."),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Body."])
    }

    // MARK: - Removal fixtures: social clusters

    func testRemovesSocialFollowClusterOfListItems() {
        let blocks = [
            p("Real ending paragraph."),
            li("Twitter"),
            li("Facebook"),
            li("LinkedIn"),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Real ending paragraph."])
    }

    func testRemovesAdjacentShareRow() {
        // Consecutive short share CTAs gate each other in.
        let blocks = [
            p("Prose."),
            p("Share on Twitter"),
            p("Share on Facebook"),
            p("Copy link"),
        ]
        XCTAssertEqual(keptTexts(blocks), ["Prose."])
    }

    // MARK: - Counter-fixtures: legit content must survive

    func testKeepsRealSignInSentenceInProse() {
        let blocks = [
            p("Before you can export, you need to sign in to your bank's portal and download the CSV."),
        ]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    func testKeepsSignInAsTutorialHeading() {
        // Headings are exempt from the exact auth/social rules.
        let blocks = [
            h("Sign in"),
            p("To sign in, open the app and tap the profile icon."),
        ]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    func testKeepsShortLinkDenseParagraph() {
        let blocks = [
            p("See the docs."),
            p("Related: part one, part two."),
        ]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    func testKeepsIsolatedSocialWordInProse() {
        // A lone "Share." between real paragraphs is not clustered — survives.
        let blocks = [
            p("He looked at the button. It said one word."),
            p("Share"),
            p("He did not press it."),
        ]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    func testKeepsLongParagraphQuotingANag() {
        // Phrase rules are length-gated: prose *about* the nag survives.
        let blocks = [
            p("""
            Every time I open the site it begs me to join Medium for free to get \
            updates from this writer, which is exactly the kind of interruption \
            that made me build a read-later app in the first place, and I think \
            that says something about the state of the modern web.
            """),
        ]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    func testKeepsMinReadInsideProse() {
        let blocks = [p("It was a 6 min read that changed how I think.")]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    func testNeverFiltersArticleToEmpty() {
        // Pathological page that is nothing but nags: filtering all of it
        // would leave zero text, so the filter backs off entirely.
        let blocks = [
            p("Sign in"),
            p("2 free stories left"),
        ]
        let result = CruftFilter.filter(blocks)
        XCTAssertEqual(result.kept, blocks)
        XCTAssertEqual(result.removed, [])
    }

    func testPreformattedIsNeverCruft() {
        // Code samples can contain anything — including exact rule strings.
        let blocks = [
            ArticleBlock(type: .preformatted, text: "sign in"),
            p("Explanation of the code above."),
        ]
        XCTAssertEqual(CruftFilter.filter(blocks).removed, [])
    }

    // MARK: - Offset-space parity

    func testDerivePlainTextMatchesFilteredJoin() {
        let blocks = [
            h("Title", 1),
            p("One."),
            p("Get Jane's stories in your inbox"),
            p("Two."),
        ]
        let kept = CruftFilter.filter(blocks).kept
        XCTAssertEqual(ArticleBlocks.derivePlainText(kept), "Title\n\nOne.\n\nTwo.")
    }

    // MARK: - Quality-gate composition (ArticleParser.gateAndFilter)

    @MainActor
    func testGateAndFilterRemovesCruftFromLongArticle() {
        // 80 words of prose plus a nag: filter fires, gate still passes.
        let prose = (0 ..< 8).map { i in
            p("Paragraph number \(i) carries eight genuine words of article prose.")
        }
        let blocks = prose + [p("Join Medium for free to get updates from this writer.")]
        let result = ArticleParser.gateAndFilter(mapped: blocks, legacyText: "", linkDensity: 0.05)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.removed.count, 1)
        XCTAssertEqual(result?.blocks.count, 8)
        XCTAssertFalse(result?.plainText.contains("Join Medium") ?? true)
    }

    @MainActor
    func testGateAndFilterBacksOffWhenFilteringWouldFailALegitShortArticle() {
        // 6 x 8 = 48 words of prose + a 3-word auth CTA = 51 words total.
        // Post-filter the article drops to 48 words — below the gate's
        // 50-word minimum — but unfiltered it passes. The filter must back
        // off (keep the cruft) rather than reject a real article.
        let prose = (0 ..< 6).map { i in
            p("Legit paragraph \(i) holding exactly eight words total.")
        }
        let blocks = prose + [p("Continue with Google")]
        let result = ArticleParser.gateAndFilter(mapped: blocks, legacyText: "", linkDensity: 0.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.blocks.count, 7, "filter should back off, keeping all blocks")
        XCTAssertEqual(result?.removed, [])
        XCTAssertTrue(result?.plainText.contains("Continue with Google") ?? false)
    }

    @MainActor
    func testGateAndFilterStillRejectsNavShells() {
        // A nav shell — a handful of short link-like lines — fails the gate
        // both filtered and unfiltered: gateAndFilter returns nil and the
        // parser's retry loop / .lowQuality path takes over.
        let blocks = [p("Sitemap"), p("About"), p("Careers"), p("Contact us"), p("Press")]
        XCTAssertNil(ArticleParser.gateAndFilter(mapped: blocks, legacyText: "", linkDensity: 0.9))
    }

    @MainActor
    func testGateAndFilterEmptyBlocksUsesLegacyTextUnfiltered() {
        // Legacy fallback path (no typed blocks): text passes through
        // unfiltered by design — deferred per the design doc.
        let legacy = Array(repeating: "word", count: 60).joined(separator: " ")
        let result = ArticleParser.gateAndFilter(mapped: [], legacyText: legacy, linkDensity: 0.0)
        XCTAssertEqual(result?.plainText, legacy)
        XCTAssertEqual(result?.blocks, [])
        XCTAssertEqual(result?.removed, [])
    }

    // MARK: - Debug persistence on Article

    @MainActor
    func testApplyRecordsRemovedCruftForDebugging() throws {
        let article = Article(url: URL(string: "https://example.com/a")!, title: "t")
        let kept = [p("Prose that stays.")]
        let removed = [p("Join Medium for free to get updates from this writer.")]
        let parsed = ArticleParser.Parsed(
            title: "t", author: nil, siteName: nil,
            plainText: "Prose that stays.", extractedHTML: "",
            heroImageURL: nil, estimatedReadingMinutes: 1,
            blocks: kept, removedBlocks: removed, isPaywalledPartial: false
        )
        article.apply(parsed, updateTitle: false)
        XCTAssertTrue(article.wasCruftFiltered)
        XCTAssertEqual(article.removedCruftBlocks, removed)

        // A later parse that removes nothing clears both debug fields so they
        // always describe the current text.
        let clean = ArticleParser.Parsed(
            title: "t", author: nil, siteName: nil,
            plainText: "Prose that stays.", extractedHTML: "",
            heroImageURL: nil, estimatedReadingMinutes: 1,
            blocks: kept, removedBlocks: [], isPaywalledPartial: false
        )
        article.apply(clean, updateTitle: false)
        XCTAssertFalse(article.wasCruftFiltered)
        XCTAssertNil(article.removedCruftBlocks)
    }

    // MARK: - Normalization

    func testNormalizeStripsEdgePunctuationAndCase() {
        XCTAssertEqual(CruftFilter.normalize("  Sign In.  "), "sign in")
        XCTAssertEqual(CruftFilter.normalize("· Follow ·"), "follow")
        XCTAssertEqual(CruftFilter.normalize("Member-only story"), "member-only story")
        // Curly apostrophe straightens so phrase tables stay ASCII.
        XCTAssertEqual(CruftFilter.normalize("Jane\u{2019}s stories"), "jane's stories")
    }
}
