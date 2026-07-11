import XCTest
@testable import ReadLater

final class HighlightAnchorTests: XCTestCase {

    func testExactOffsetsWin() {
        let text = "The quick brown fox jumps over the lazy dog."
        let located = HighlightAnchor.locate(in: text, startOffset: 4, endOffset: 15, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, false)
        XCTAssertEqual(located?.startOffset, 4)
    }

    func testOffsetsAreUTF16() {
        // "🎉🎉 The " = 2+2 (emoji, non-BMP) + 1 + 3 + 1 = 9 UTF-16 units.
        // A Character-based interpretation would put "quick" at offset 7.
        let text = "🎉🎉 The quick brown fox jumps."
        let located = HighlightAnchor.locate(in: text, startOffset: 9, endOffset: 20, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, false)
        XCTAssertEqual(located.map { String(text[$0.range]) }, "quick brown")
    }

    func testCharacterOffsetsFromLegacyDataSelfHeal() {
        // Offsets stored under the old Character interpretation (7) no longer
        // line up — the quoted-text search must repair to UTF-16 (9).
        let text = "🎉🎉 The quick brown fox jumps."
        let located = HighlightAnchor.locate(in: text, startOffset: 7, endOffset: 18, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, true)
        XCTAssertEqual(located?.startOffset, 9)
        XCTAssertEqual(located?.endOffset, 20)
    }

    func testReanchorAfterShift() {
        // Article was re-parsed and a prefix was added; offsets are now wrong.
        let text = "Published Jan 1. The quick brown fox jumps over the lazy dog."
        let located = HighlightAnchor.locate(in: text, startOffset: 4, endOffset: 15, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, true)
        XCTAssertEqual(located?.startOffset, 21) // "quick brown" starts at 21 (UTF-16)
    }

    func testWhitespaceCollapseFallback() {
        // Quoted text had a single space; re-parsed body has a newline.
        let text = "The quick\nbrown fox jumps."
        let located = HighlightAnchor.locate(in: text, startOffset: 0, endOffset: 11, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, true)
        XCTAssertEqual(located.map { String(text[$0.range]) }, "quick\nbrown")
    }

    func testWhitespaceCollapseFallbackWithEmojiPrefix() {
        let text = "🎉 intro\n\nThe quick\nbrown fox jumps."
        let located = HighlightAnchor.locate(in: text, startOffset: 0, endOffset: 5, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located.map { String(text[$0.range]) }, "quick\nbrown")
    }

    func testMissingReturnsNil() {
        let text = "Totally different content."
        XCTAssertNil(HighlightAnchor.locate(in: text, startOffset: 0, endOffset: 5, quotedText: "not there"))
    }
}
