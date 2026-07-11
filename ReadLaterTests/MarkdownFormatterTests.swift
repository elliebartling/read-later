import XCTest
@testable import ReadLater

final class MarkdownFormatterTests: XCTestCase {

    private func makeArticle() -> Article {
        Article(
            url: URL(string: "https://example.com/a")!,
            title: "How things work",
            author: "A. Writer",
            siteName: "Example",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plainText: "The quick brown fox jumps over the lazy dog.",
            parseStatus: .ready
        )
    }

    private func makeHighlight(for article: Article) -> Highlight {
        Highlight(
            article: article,
            startOffset: 4,
            endOffset: 15,
            quotedText: "quick brown",
            color: .yellow,
            note: "Meaningful phrase."
        )
    }

    func testFreshRenderHasFrontmatterAndManagedSection() {
        let article = makeArticle()
        let h = makeHighlight(for: article)
        let md = MarkdownFormatter.render(.init(article: article, highlights: [h]))

        XCTAssertTrue(md.contains("title: \"How things work\""))
        XCTAssertTrue(md.contains("url: \"https://example.com/a\""))
        XCTAssertTrue(md.contains(MarkdownFormatter.managedSectionStart))
        XCTAssertTrue(md.contains(MarkdownFormatter.managedSectionEnd))
        XCTAssertTrue(md.contains("> quick brown (color:: yellow)"))
        XCTAssertTrue(md.contains("**Note:** Meaningful phrase."))
        // Wikilink form would pollute the Obsidian graph with a node per color.
        XCTAssertFalse(md.contains("[[color::"))
    }

    func testMergePreservesUserEditsOutsideMarkers() {
        let article = makeArticle()
        let h = makeHighlight(for: article)
        let original = MarkdownFormatter.render(.init(article: article, highlights: [h]))

        // Simulate the user annotating the exported note in Obsidian.
        let edited = "MY NOTES ABOVE\n" + original + "\nMY NOTES BELOW\n"

        let secondHighlight = Highlight(
            article: article,
            startOffset: 20,
            endOffset: 25,
            quotedText: "jumps",
            color: .blue
        )
        let merged = MarkdownFormatter.merge(
            existing: edited,
            input: .init(article: article, highlights: [h, secondHighlight])
        )

        XCTAssertTrue(merged.contains("MY NOTES ABOVE"))
        XCTAssertTrue(merged.contains("MY NOTES BELOW"))
        XCTAssertTrue(merged.contains("> quick brown (color:: yellow)"))
        XCTAssertTrue(merged.contains("> jumps (color:: blue)"))
        // Markers appear exactly once each after the merge.
        XCTAssertEqual(merged.components(separatedBy: MarkdownFormatter.managedSectionStart).count, 2)
        XCTAssertEqual(merged.components(separatedBy: MarkdownFormatter.managedSectionEnd).count, 2)
    }

    func testMergeAppendsWhenMarkersMissing() {
        let article = makeArticle()
        let h = makeHighlight(for: article)
        let userFile = "A note the user wrote by hand, no markers anywhere.\n"

        let merged = MarkdownFormatter.merge(
            existing: userFile,
            input: .init(article: article, highlights: [h])
        )

        XCTAssertTrue(merged.hasPrefix("A note the user wrote by hand"))
        XCTAssertTrue(merged.contains(MarkdownFormatter.managedSectionStart))
        XCTAssertTrue(merged.contains("> quick brown (color:: yellow)"))
    }

    func testSlugStrategy() {
        let article = Article(
            url: URL(string: "https://example.com/a")!,
            title: "How Things Work — Part 1!",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let slug = MarkdownFormatter.slug(for: article)
        XCTAssertTrue(slug.hasSuffix("how-things-work-part-1"))
    }
}
