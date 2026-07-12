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

    // MARK: - Task 2: blocks(fromJS:baseURL:) mapping

    private let base = URL(string: "https://example.com/a/b.html")!

    func testBlocksFromJSMapsEveryType() {
        let raw: [[String: Any]] = [
            ["type": "heading", "text": "Title", "level": 2],
            ["type": "paragraph", "text": "A paragraph."],
            ["type": "listItem", "text": "First", "listStyle": "ordered"],
            ["type": "listItem", "text": "Bullet", "listStyle": "unordered"],
            ["type": "blockquote", "text": "A quote"],
            ["type": "preformatted", "text": "let x = 1\n  y = 2"],
            ["type": "image", "src": "https://cdn.example.com/pic.jpg", "alt": "A cat", "width": 640, "height": 480],
            ["type": "caption", "text": "Figure 1"],
            ["type": "divider"],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.count, 9)

        XCTAssertEqual(blocks[0].type, .heading)
        XCTAssertEqual(blocks[0].text, "Title")
        XCTAssertEqual(blocks[0].level, 2)

        XCTAssertEqual(blocks[1].type, .paragraph)
        XCTAssertEqual(blocks[1].text, "A paragraph.")

        XCTAssertEqual(blocks[2].type, .listItem)
        XCTAssertEqual(blocks[2].listStyle, .ordered)
        XCTAssertEqual(blocks[3].listStyle, .unordered)

        XCTAssertEqual(blocks[4].type, .blockquote)
        XCTAssertEqual(blocks[4].text, "A quote")

        XCTAssertEqual(blocks[5].type, .preformatted)
        XCTAssertEqual(blocks[5].text, "let x = 1\n  y = 2")

        XCTAssertEqual(blocks[6].type, .image)
        XCTAssertEqual(blocks[6].src, URL(string: "https://cdn.example.com/pic.jpg"))
        XCTAssertEqual(blocks[6].alt, "A cat")
        XCTAssertEqual(blocks[6].width, 640)
        XCTAssertEqual(blocks[6].height, 480)

        XCTAssertEqual(blocks[7].type, .caption)
        XCTAssertEqual(blocks[7].text, "Figure 1")

        XCTAssertEqual(blocks[8].type, .divider)
    }

    func testBlocksFromJSResolvesRelativeImageURL() {
        let raw: [[String: Any]] = [
            ["type": "image", "src": "img/pic.png"],
            ["type": "image", "src": "/root.png"],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].src, URL(string: "https://example.com/a/img/pic.png"))
        XCTAssertEqual(blocks[1].src, URL(string: "https://example.com/root.png"))
    }

    func testBlocksFromJSSkipsTrackingPixels() {
        let raw: [[String: Any]] = [
            ["type": "image", "src": "https://cdn.example.com/spy.gif", "width": 1, "height": 1],
            ["type": "image", "src": "https://cdn.example.com/spy2.gif", "width": 300, "height": 2],
            ["type": "image", "src": "https://cdn.example.com/ok.jpg", "width": 300, "height": 200],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].src, URL(string: "https://cdn.example.com/ok.jpg"))
    }

    func testBlocksFromJSSkipsDataURIAndMissingSrc() {
        let raw: [[String: Any]] = [
            ["type": "image", "src": "data:image/png;base64,iVBORw0KGgo="],
            ["type": "image", "alt": "no src here"],
            ["type": "image", "src": ""],
            ["type": "image", "src": "https://cdn.example.com/keep.jpg"],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].src, URL(string: "https://cdn.example.com/keep.jpg"))
    }

    func testBlocksFromJSDropsUnknownTypesButKeepsRest() {
        let raw: [[String: Any]] = [
            ["type": "paragraph", "text": "before"],
            ["type": "hologram", "text": "??"],
            ["type": "divider"],
            ["type": "paragraph", "text": "after"],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.map(\.type), [.paragraph, .divider, .paragraph])
        XCTAssertEqual(blocks.first?.text, "before")
        XCTAssertEqual(blocks.last?.text, "after")
    }

    func testBlocksFromJSHandlesNumericAsDoubleOrNSNumber() {
        let raw: [[String: Any]] = [
            ["type": "heading", "text": "H", "level": Double(3)],
            ["type": "image", "src": "https://cdn.example.com/z.jpg",
             "width": NSNumber(value: 800), "height": Double(600)],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks[0].level, 3)
        XCTAssertEqual(blocks[1].width, 800)
        XCTAssertEqual(blocks[1].height, 600)
    }

    func testDerivePlainTextParityWithLegacyJoinForTextOnlyFixture() {
        let texts = ["Title", "One", "A caption", "Two"]
        let raw: [[String: Any]] = [
            ["type": "heading", "text": texts[0], "level": 1],
            ["type": "paragraph", "text": texts[1]],
            ["type": "caption", "text": texts[2]],
            ["type": "paragraph", "text": texts[3]],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(ArticleBlocks.derivePlainText(blocks),
                       texts.joined(separator: "\n\n"))
    }
}
