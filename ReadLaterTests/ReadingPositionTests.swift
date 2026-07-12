import XCTest
import UIKit
@testable import ReadLater

final class ReadingPositionTests: XCTestCase {

    typealias Coordinator = HighlightableTextView.Coordinator

    func testRestoreOffsetPlacesCaretAtViewportTop() {
        // The saved character's caret sits at y=2200 in content space; with a
        // 50pt top inset it should land 50pt above the caret so the caret is
        // flush with the top of the visible text area.
        let restored = Coordinator.restoreOffsetY(
            caretMinY: 2200,
            contentHeight: 5000,
            viewportHeight: 800,
            topInset: 50,
            bottomInset: 0
        )
        XCTAssertEqual(restored, 2150, accuracy: 0.001)
    }

    func testRestoreOffsetClampsToTop() {
        // A caret near the very top must not scroll above the content.
        let restored = Coordinator.restoreOffsetY(
            caretMinY: 10,
            contentHeight: 5000,
            viewportHeight: 800,
            topInset: 50,
            bottomInset: 34
        )
        XCTAssertEqual(restored, -50, accuracy: 0.001)
    }

    func testRestoreOffsetClampsToBottom() {
        // A caret deep in the article can't scroll past the last full screen.
        let content: CGFloat = 5000
        let viewport: CGFloat = 800
        let bottomInset: CGFloat = 34
        let restored = Coordinator.restoreOffsetY(
            caretMinY: 4990,
            contentHeight: content,
            viewportHeight: viewport,
            topInset: 0,
            bottomInset: bottomInset
        )
        XCTAssertEqual(restored, content - viewport + bottomInset, accuracy: 0.001)
    }

    func testRestoreOffsetShortContentStaysAtTop() {
        // Content that fits within the viewport has no scroll range.
        let restored = Coordinator.restoreOffsetY(
            caretMinY: 300,
            contentHeight: 400,
            viewportHeight: 800,
            topInset: 50,
            bottomInset: 0
        )
        XCTAssertEqual(restored, -50, accuracy: 0.001)
    }
}
