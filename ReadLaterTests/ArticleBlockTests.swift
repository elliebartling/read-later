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

    func testBlocksFromJSReadsMarkerBakedFlag() {
        // The JS walk now bakes list markers into `text` and flags the block so
        // the block reader skips its composed marker. The mapper must carry the
        // flag through; blocks without the key decode as nil (pre-baking blocks).
        let raw: [[String: Any]] = [
            ["type": "listItem", "text": "• Baked bullet", "listStyle": "unordered", "markerBaked": true],
            ["type": "listItem", "text": "Legacy bullet", "listStyle": "unordered"],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].markerBaked, true)
        XCTAssertEqual(blocks[0].text, "• Baked bullet")
        XCTAssertNil(blocks[1].markerBaked)
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

    // MARK: - Task 5: ArticleImageCache pure helpers

    func testCacheKeyCombinesURLAndTruncatedTargetWidth() {
        let url = URL(string: "https://cdn.example.com/pic.jpg")!
        XCTAssertEqual(
            ArticleImageCache.cacheKey(url: url, targetWidth: 320),
            "https://cdn.example.com/pic.jpg#320"
        )
        // Fractional widths truncate toward zero (matches "\(Int(targetWidth))").
        XCTAssertEqual(
            ArticleImageCache.cacheKey(url: url, targetWidth: 320.7),
            "https://cdn.example.com/pic.jpg#320"
        )
        // Distinct widths must yield distinct keys so we don't serve a
        // too-small decode when the layout gets wider.
        XCTAssertNotEqual(
            ArticleImageCache.cacheKey(url: url, targetWidth: 320),
            ArticleImageCache.cacheKey(url: url, targetWidth: 640)
        )
    }

    func testMaxPixelSizeScalesWidthByDisplayScaleAndRounds() {
        XCTAssertEqual(ArticleImageCache.maxPixelSize(targetWidth: 320, scale: 3), 960)
        XCTAssertEqual(ArticleImageCache.maxPixelSize(targetWidth: 200, scale: 2), 400)
        // Rounds to the nearest whole pixel (200.8 -> 201).
        XCTAssertEqual(ArticleImageCache.maxPixelSize(targetWidth: 100.4, scale: 2), 201)
        // Non-positive scale falls back to 1x rather than producing 0.
        XCTAssertEqual(ArticleImageCache.maxPixelSize(targetWidth: 320, scale: 0), 320)
        // Never returns below 1 (ImageIO rejects a 0 max pixel size).
        XCTAssertEqual(ArticleImageCache.maxPixelSize(targetWidth: 0, scale: 3), 1)
    }

    // MARK: - Task 7: block reader layout helpers

    func testTextBlockRangesByIndexAlignsToBlockIndexAndSkipsNonText() {
        let blocks: [ArticleBlock] = [
            block(.paragraph, "One"),                    // idx 0: base 0, len 3
            ArticleBlock(type: .image, src: nil),        // idx 1: no range
            block(.paragraph, ""),                       // idx 2: empty -> no range
            block(.paragraph, "Two"),                    // idx 3: base 5, len 3
            block(.divider),                             // idx 4: no range
            block(.heading, "Head"),                     // idx 5: base 10, len 4
        ]
        let ranges = ArticleBlocks.textBlockRangesByIndex(blocks)
        XCTAssertEqual(ranges[0], NSRange(location: 0, length: 3))
        XCTAssertNil(ranges[1])
        XCTAssertNil(ranges[2])
        XCTAssertEqual(ranges[3], NSRange(location: 5, length: 3))
        XCTAssertNil(ranges[4])
        XCTAssertEqual(ranges[5], NSRange(location: 10, length: 4))
        // Base offsets match derivePlainText: "One\n\nTwo\n\nHead".
        XCTAssertEqual(ArticleBlocks.derivePlainText(blocks), "One\n\nTwo\n\nHead")
    }

    func testPreformattedCodeBlockPreservesWhitespaceAndOffsetSpace() {
        // A multi-line, indented shell command like the one in Ellen's
        // TestFlight screenshot. The code-block redesign is view-only, so the
        // block's contribution to the highlight offset space (plainText +
        // UTF-16 ranges) must be byte-identical to any other text-bearing block.
        let code = "brew install foo \\\n  --with-bar \\\n  --prefix=/usr/local"
        let raw: [[String: Any]] = [
            ["type": "paragraph", "text": "Intro"],
            ["type": "preformatted", "text": code],
            ["type": "paragraph", "text": "Outro"],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: base)
        XCTAssertEqual(blocks[1].type, .preformatted)
        // Internal whitespace/newlines are preserved verbatim.
        XCTAssertEqual(blocks[1].text, code)
        XCTAssertTrue(blocks[1].type.isTextBearing)

        // The code block joins into plainText exactly like a paragraph.
        let plainText = ArticleBlocks.derivePlainText(blocks)
        XCTAssertEqual(plainText, "Intro\n\n\(code)\n\nOutro")

        // Its UTF-16 range within plainText is correct (base after "Intro\n\n").
        let ranges = ArticleBlocks.textBlockRangesByIndex(blocks)
        let codeLen = (code as NSString).length
        XCTAssertEqual(ranges[1], NSRange(location: 7, length: codeLen))
        // The following block resumes right after the code + "\n\n".
        XCTAssertEqual(ranges[2], NSRange(location: 7 + codeLen + 2, length: 5))
    }

    func testClipHighlightSpansParagraphBreakIntoPartialLocalRanges() {
        // Two blocks: A = [0,5), B = [7,12) with a "\n\n" break between them.
        let a = NSRange(location: 0, length: 5)
        let b = NSRange(location: 7, length: 5)
        // A cross-paragraph highlight covering global 3..<9.
        let global = NSRange(location: 3, length: 6)
        XCTAssertEqual(ArticleBlocks.clipHighlight(global: global, toBlock: a),
                       NSRange(location: 3, length: 2))   // A[3..<5], local
        XCTAssertEqual(ArticleBlocks.clipHighlight(global: global, toBlock: b),
                       NSRange(location: 0, length: 2))   // B[7..<9] -> local 0..<2
        // A highlight fully inside B shifts to local coordinates.
        XCTAssertEqual(ArticleBlocks.clipHighlight(global: NSRange(location: 8, length: 3), toBlock: b),
                       NSRange(location: 1, length: 3))
        // No overlap -> nil.
        XCTAssertNil(ArticleBlocks.clipHighlight(global: NSRange(location: 5, length: 2), toBlock: a))
    }

    func testListMarkersResetOrderedNumberingPerConsecutiveRun() {
        let blocks: [ArticleBlock] = [
            block(.paragraph, "intro"),
            ArticleBlock(type: .listItem, text: "a", listStyle: .unordered),
            ArticleBlock(type: .listItem, text: "b", listStyle: .unordered),
            block(.paragraph, "break"),
            ArticleBlock(type: .listItem, text: "1", listStyle: .ordered),
            ArticleBlock(type: .listItem, text: "2", listStyle: .ordered),
            ArticleBlock(type: .listItem, text: "3", listStyle: .ordered),
        ]
        let markers = ArticleBlocks.listMarkers(blocks)
        XCTAssertNil(markers[0])
        XCTAssertEqual(markers[1], "•")
        XCTAssertEqual(markers[2], "•")
        XCTAssertNil(markers[3])
        XCTAssertEqual(markers[4], "1.")   // ordinal resets at the run start
        XCTAssertEqual(markers[5], "2.")
        XCTAssertEqual(markers[6], "3.")
    }

    func testListMarkersSkipsBakedItemsToAvoidDoubleMarking() {
        // Blocks whose marker is baked into text get NO composed marker — the
        // block reader renders them like paragraphs, so it never double-marks.
        let blocks: [ArticleBlock] = [
            ArticleBlock(type: .listItem, text: "• a", listStyle: .unordered, markerBaked: true),
            ArticleBlock(type: .listItem, text: "1. b", listStyle: .ordered, markerBaked: true),
        ]
        XCTAssertTrue(ArticleBlocks.listMarkers(blocks).isEmpty)
    }

    func testParagraphBlockIndicesMapMultilinePreformattedToOneBlock() {
        let blocks: [ArticleBlock] = [
            block(.heading, "Title"),                    // 1 paragraph -> block 0
            block(.paragraph, "One"),                    // 1 paragraph -> block 1
            block(.preformatted, "let x = 1\n  y = 2"),  // 2 paragraphs -> block 2
            ArticleBlock(type: .image, src: nil),        // no paragraph
            block(.paragraph, "Two"),                    // 1 paragraph -> block 4
        ]
        XCTAssertEqual(ArticleBlocks.paragraphBlockIndices(blocks), [0, 1, 2, 2, 4])

        // Correspondence check: the mapping must match how ReaderView derives
        // paragraphs from plainText (split on "\n", trim, drop empties).
        let plainText = ArticleBlocks.derivePlainText(blocks)
        let paragraphCount = plainText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
        XCTAssertEqual(ArticleBlocks.paragraphBlockIndices(blocks).count, paragraphCount)
    }
}
