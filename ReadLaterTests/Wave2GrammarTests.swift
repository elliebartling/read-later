import XCTest
import SwiftUI
@testable import ReadLater

/// Wave 2 — Grammar. Pins the pure rules the wave introduced: the metadata
/// grammar (R2), the single source-string format (R3), and the reader-structure
/// helpers behind the hanging indent, list grouping and inline code (fix #4).
final class Wave2GrammarTests: XCTestCase {

    // MARK: - R2, the metadata line

    func testMetadataJoinsFieldsInFixedOrder() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let meta = RowMetadata(source: "overreacted.io", date: date, details: ["33 min", "2 highlights"])
        let expected = [
            "overreacted.io",
            date.formatted(.relative(presentation: .named)),
            "33 min",
            "2 highlights",
        ].joined(separator: " · ")
        XCTAssertEqual(meta.text, expected)
    }

    func testMetadataOmitsMissingFieldsWithoutStrandingSeparators() {
        // A per-feed list drops `source` because it duplicates the nav title.
        let meta = RowMetadata(source: nil, date: nil, details: ["Saved"])
        XCTAssertEqual(meta.text, "Saved")
        XCTAssertFalse(meta.text.hasPrefix(" · "))
    }

    func testMetadataDropsEmptyStrings() {
        let meta = RowMetadata(source: "", date: nil, details: ["", "Video"])
        XCTAssertEqual(meta.text, "Video")
    }

    func testMetadataIsEmptyWhenNothingToSay() {
        XCTAssertEqual(RowMetadata().text, "")
    }

    /// R7 — a failed parse leads the line, because it is the thing you most
    /// need to know about that row.
    func testFailedParseLeadsTheMetadataLine() {
        let meta = RowMetadata(source: "example.com", details: [], isFailed: true)
        XCTAssertEqual(meta.text, "Couldn't parse · example.com")
    }

    // MARK: - R3, one source string

    func testSourceStringPrefersSiteName() {
        XCTAssertEqual(
            SourceIdentity.sourceString(siteName: "YouTube", host: "www.youtube.com"),
            "YouTube"
        )
    }

    func testSourceStringStripsWWWFromHost() {
        XCTAssertEqual(SourceIdentity.sourceString(siteName: nil, host: "www.reddit.com"), "reddit.com")
        XCTAssertEqual(SourceIdentity.sourceString(siteName: nil, host: "overreacted.io"), "overreacted.io")
    }

    func testSourceStringIgnoresBlankSiteName() {
        XCTAssertEqual(SourceIdentity.sourceString(siteName: "   ", host: "example.com"), "example.com")
    }

    func testSourceStringIsNilWithNothingToShow() {
        XCTAssertNil(SourceIdentity.sourceString(siteName: nil, host: nil))
        XCTAssertNil(SourceIdentity.sourceString(siteName: "", host: ""))
    }

    // MARK: - Hanging indents: the baked marker

    func testBakedMarkerPrefixReadsBulletAndOrdinal() {
        XCTAssertEqual(ArticleBlocks.bakedMarkerPrefix("• First item"), "• ")
        XCTAssertEqual(ArticleBlocks.bakedMarkerPrefix("3. Third item"), "3. ")
        XCTAssertEqual(ArticleBlocks.bakedMarkerPrefix("12. Twelfth"), "12. ")
    }

    /// Nested items carry two non-breaking spaces per level ahead of the
    /// marker; the indent is part of the prefix, so the hanging indent
    /// measures the whole thing.
    func testBakedMarkerPrefixIncludesNestingIndent() {
        let nested = "\u{00a0}\u{00a0}• Nested"
        XCTAssertEqual(ArticleBlocks.bakedMarkerPrefix(nested), "\u{00a0}\u{00a0}• ")
    }

    func testBakedMarkerPrefixRejectsNonMarkers() {
        XCTAssertNil(ArticleBlocks.bakedMarkerPrefix("Ordinary paragraph"))
        XCTAssertNil(ArticleBlocks.bakedMarkerPrefix("•No space"))
        XCTAssertNil(ArticleBlocks.bakedMarkerPrefix("3.No space"))
        XCTAssertNil(ArticleBlocks.bakedMarkerPrefix(""))
    }

    // MARK: - List ranges over plainText (the plain reader's route)

    private func listBlocks() -> [ArticleBlock] {
        [
            ArticleBlock(type: .paragraph, text: "Intro paragraph."),
            ArticleBlock(type: .listItem, text: "• One", listStyle: .unordered, markerBaked: true),
            ArticleBlock(type: .listItem, text: "• Two", listStyle: .unordered, markerBaked: true),
            ArticleBlock(type: .paragraph, text: "Outro paragraph."),
        ]
    }

    func testListItemRangesLocateEveryItemInPlainText() {
        let blocks = listBlocks()
        let text = ArticleBlocks.derivePlainText(blocks)
        let items = ArticleBlocks.listItemRanges(blocks, in: text)
        XCTAssertEqual(items.count, 2)
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: items[0].range), "• One")
        XCTAssertEqual(ns.substring(with: items[1].range), "• Two")
        XCTAssertEqual(items[0].markerPrefix, "• ")
    }

    /// Only an item followed by another item closes its spacing; the last item
    /// keeps full paragraph spacing so the list separates from what follows.
    func testListItemRangesFlagOnlyContinuingItems() {
        let blocks = listBlocks()
        let items = ArticleBlocks.listItemRanges(blocks, in: ArticleBlocks.derivePlainText(blocks))
        XCTAssertTrue(items[0].continuesList)
        XCTAssertFalse(items[1].continuesList)
    }

    /// Same contract as `quoteRanges`: a drifted `plainText`/blocks pair
    /// degrades to no styling rather than indenting the wrong paragraph.
    func testListItemRangesRefuseDriftedPlainText() {
        let blocks = listBlocks()
        let items = ArticleBlocks.listItemRanges(blocks, in: "Completely different text.")
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Inline code ranges

    func testInlineCodeRangesLiftBlockLocalRangesIntoPlainText() {
        let blocks = [
            ArticleBlock(type: .paragraph, text: "First."),
            ArticleBlock(type: .paragraph, text: "Call foo() now.", codeRanges: [[5, 5]]),
        ]
        let text = ArticleBlocks.derivePlainText(blocks)
        let ranges = ArticleBlocks.inlineCodeRanges(blocks, in: text)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual((text as NSString).substring(with: ranges[0]), "foo()")
    }

    func testInlineCodeRangesDropRangesOutsideTheirBlock() {
        let blocks = [ArticleBlock(type: .paragraph, text: "Short.", codeRanges: [[3, 99], [0, 0]])]
        let ranges = ArticleBlocks.inlineCodeRanges(blocks, in: ArticleBlocks.derivePlainText(blocks))
        XCTAssertTrue(ranges.isEmpty)
    }

    func testInlineCodeRangesRefuseDriftedPlainText() {
        let blocks = [ArticleBlock(type: .paragraph, text: "Call foo() now.", codeRanges: [[5, 5]])]
        XCTAssertTrue(ArticleBlocks.inlineCodeRanges(blocks, in: "Something else entirely.").isEmpty)
    }

    /// The whole point of carrying spans as metadata: the text — and therefore
    /// every UTF-16 highlight offset over it — is byte-identical either way.
    func testInlineCodeDoesNotChangePlainText() {
        let plain = [ArticleBlock(type: .paragraph, text: "Call foo() now.")]
        let coded = [ArticleBlock(type: .paragraph, text: "Call foo() now.", codeRanges: [[5, 5]])]
        XCTAssertEqual(ArticleBlocks.derivePlainText(plain), ArticleBlocks.derivePlainText(coded))
    }

    // MARK: - Parser decoding

    func testParserDecodesInlineCodeRanges() {
        let raw: [[String: Any]] = [
            ["type": "paragraph", "text": "Call foo() now.", "codeRanges": [[5, 5]]],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: URL(string: "https://example.com")!)
        XCTAssertEqual(blocks.first?.codeRanges ?? [], [[5, 5]])
    }

    func testParserDropsMalformedInlineCodeRanges() {
        let raw: [[String: Any]] = [
            ["type": "paragraph", "text": "Text", "codeRanges": [[1], [-1, 2], [0, 0]]],
        ]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: URL(string: "https://example.com")!)
        XCTAssertNil(blocks.first?.codeRanges)
    }

    func testParserLeavesCodeRangesNilWhenAbsent() {
        let raw: [[String: Any]] = [["type": "paragraph", "text": "Text"]]
        let blocks = ArticleParser.blocks(fromJS: raw, baseURL: URL(string: "https://example.com")!)
        XCTAssertNil(blocks.first?.codeRanges)
    }

    // MARK: - Reader typography numbers (shared by BOTH readers)

    func testListItemSpacingIsTighterThanParagraphSpacing() {
        for paragraph in stride(from: 4.0, through: 24.0, by: 2.0) {
            let list = ReaderTypography.listItemSpacing(paragraphSpacing: paragraph)
            XCTAssertLessThan(list, paragraph, "a list must read tighter than prose at \(paragraph)pt")
            XCTAssertGreaterThan(list, 0)
        }
    }

    func testListItemSpacingNeverCollapsesToZero() {
        XCTAssertGreaterThanOrEqual(ReaderTypography.listItemSpacing(paragraphSpacing: 0), 2)
    }

    func testMarkerWidthIsPositiveAndOrdersByMarkerLength() {
        let font = UIFont.systemFont(ofSize: 18)
        let bullet = ReaderTypography.markerWidth("• ", font: font)
        let nested = ReaderTypography.markerWidth("\u{00a0}\u{00a0}• ", font: font)
        XCTAssertGreaterThan(bullet, 0)
        XCTAssertGreaterThan(nested, bullet)
        XCTAssertEqual(ReaderTypography.markerWidth("", font: font), 0)
    }

    func testInlineCodeFontIsMonospacedAndSlightlySmaller() {
        let code = ReaderTypography.inlineCodeFont(bodySize: 18)
        XCTAssertLessThan(code.pointSize, 18)
        XCTAssertTrue(code.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    // MARK: - BR3, the three kind silhouettes

    /// All three exist, all three are drawn, and all three take the SAME stroke
    /// at the same optical size — the whole reason they were redrawn.
    func testEveryKindHasASilhouetteAtOneStrokeWeight() {
        let rect = CGRect(x: 0, y: 0, width: 24, height: 24)
        for kind in FeedSourceKind.allCases {
            let path = SourceKindShape(kind: kind).path(in: rect)
            XCTAssertFalse(path.isEmpty, "\(kind) has no silhouette")
            XCTAssertTrue(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect),
                          "\(kind) draws outside the 24pt grid")
        }
        let small = SourceKindShape.stroke(at: ControlTier.small.glyph)
        XCTAssertEqual(small.lineCap, .round)
        XCTAssertEqual(
            small.lineWidth,
            SourceKindShape.strokeWidth * ControlTier.small.glyph / SourceKindShape.grid,
            accuracy: 0.0001
        )
    }
}
