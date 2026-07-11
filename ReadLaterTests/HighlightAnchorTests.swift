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

    func testReanchorAfterShift() {
        // Article was re-parsed and a prefix was added; offsets are now wrong.
        let text = "Published Jan 1. The quick brown fox jumps over the lazy dog."
        let located = HighlightAnchor.locate(in: text, startOffset: 4, endOffset: 15, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, true)
        XCTAssertEqual(located?.startOffset, 20) // "quick brown" starts at 20
    }

    func testWhitespaceCollapseFallback() {
        // Quoted text had a single space; re-parsed body has a newline.
        let text = "The quick\nbrown fox jumps."
        let located = HighlightAnchor.locate(in: text, startOffset: 0, endOffset: 11, quotedText: "quick brown")
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.wasRepaired, true)
    }

    func testMissingReturnsNil() {
        let text = "Totally different content."
        XCTAssertNil(HighlightAnchor.locate(in: text, startOffset: 0, endOffset: 5, quotedText: "not there"))
    }
}
