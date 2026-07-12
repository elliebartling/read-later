import XCTest
@testable import ReadLater

final class ArticleBlockTests: XCTestCase {
    private func block(_ type: BlockType, _ text: String? = nil) -> ArticleBlock {
        ArticleBlock(type: type, text: text)
    }

    func testDerivePlainTextJoinsTextBearingBlocksOnly() {
        let blocks: [ArticleBlock] = [
            block(.heading, "Title"),
            block(.paragraph, "One"),
            ArticleBlock(type: .image, src: URL(string: "https://x/img.jpg")),
            block(.caption, "A caption"),
            block(.divider),
            block(.paragraph, "Two"),
        ]
        XCTAssertEqual(ArticleBlocks.derivePlainText(blocks), "Title\n\nOne\n\nA caption\n\nTwo")
    }

    func testBaseOffsetsAreUTF16AndSkipNonText() {
        let blocks: [ArticleBlock] = [
            block(.paragraph, "Hé"),                 // "Hé" = 2 UTF-16 units
            ArticleBlock(type: .image, src: nil),
            block(.paragraph, "🙂ok"),               // "🙂ok" = 4 UTF-16 units (emoji is a surrogate pair)
            block(.paragraph, "end"),
        ]
        let offsets = ArticleBlocks.textBlockBaseOffsets(blocks)
        // plainText = "Hé\n\n🙂ok\n\nend"
        // base("Hé") = 0; base("🙂ok") = 2 + 2 = 4; base("end") = 4 + 4 + 2 = 10
        XCTAssertEqual(offsets, [0, 4, 10])
    }

    func testCodableRoundTripAndUnknownTypeFails() throws {
        let original: [ArticleBlock] = [
            ArticleBlock(type: .heading, text: "H", level: 2),
            ArticleBlock(type: .listItem, text: "li", listStyle: .ordered),
            ArticleBlock(type: .image, src: URL(string: "https://a/b.png"), alt: "alt", width: 640, height: 480),
        ]
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([ArticleBlock].self, from: data), original)

        // Unknown type anywhere fails the whole-array decode — Article.blocks
        // then returns nil and the reader falls back to the TextKit path.
        let unknown = Data(#"[{"id":"00000000-0000-0000-0000-000000000000","type":"hologram"}]"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([ArticleBlock].self, from: unknown))
        XCTAssertNil(ArticleBlocks.decode(unknown))
    }

    func testArticleBlocksAccessorRoundTrip() throws {
        let article = Article(url: URL(string: "https://x")!, title: "t")
        XCTAssertNil(article.blocks)
        let blocks = [ArticleBlock(type: .paragraph, text: "p")]
        try article.setBlocks(blocks)
        XCTAssertEqual(article.blocks, blocks)
        XCTAssertEqual(article.blocksVersion, 1)
    }
}
