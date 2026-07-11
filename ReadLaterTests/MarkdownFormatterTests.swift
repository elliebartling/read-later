import XCTest
@testable import ReadLater

final class MarkdownFormatterTests: XCTestCase {

    func testFrontmatterAndHighlightsRender() {
        let article = Article(
            url: URL(string: "https://example.com/a")!,
            title: "How things work",
            author: "A. Writer",
            siteName: "Example",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plainText: "The quick brown fox jumps over the lazy dog.",
            parseStatus: .ready
        )
        let h = Highlight(
            article: article,
            startOffset: 4,
            endOffset: 15,
            quotedText: "quick brown",
            color: .yellow,
            note: "Meaningful phrase."
        )
        let md = MarkdownFormatter.render(.init(article: article, highlights: [h]))
        XCTAssertTrue(md.contains("title: \"How things work\""))
        XCTAssertTrue(md.contains("url: \"https://example.com/a\""))
        XCTAssertTrue(md.contains("> quick brown [[color::yellow]]"))
        XCTAssertTrue(md.contains("**Note:** Meaningful phrase."))
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
