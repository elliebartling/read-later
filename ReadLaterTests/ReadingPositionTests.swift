import XCTest
import UIKit
@testable import ReadLater

final class ReadingPositionTests: XCTestCase {

    typealias TextView = HighlightableTextView

    func testRestoreOffsetRoundTripsWithReportedProgress() {
        // scrollViewDidScroll reports (contentOffset.y + viewport) / content.
        // restoreOffset must invert that to the same contentOffset.
        let content: CGFloat = 5000
        let viewport: CGFloat = 800
        let savedOffsetY: CGFloat = 2200

        let reportedFraction = Double((savedOffsetY + viewport) / content)
        let restored = TextView.Coordinator.restoreOffset(
            fraction: reportedFraction,
            contentHeight: content,
            viewportHeight: viewport,
            topInset: 0,
            bottomInset: 0
        )
        XCTAssertEqual(restored, savedOffsetY, accuracy: 0.001)
    }

    func testRestoreOffsetClampsToTop() {
        // A tiny fraction should never scroll above the top of the content.
        let restored = TextView.Coordinator.restoreOffset(
            fraction: 0.01,
            contentHeight: 5000,
            viewportHeight: 800,
            topInset: 50,
            bottomInset: 34
        )
        XCTAssertEqual(restored, -50, accuracy: 0.001)
    }

    func testRestoreOffsetClampsToBottom() {
        // Progress at the very end lands at the maximum valid offset, not past it.
        let content: CGFloat = 5000
        let viewport: CGFloat = 800
        let bottomInset: CGFloat = 34
        let restored = TextView.Coordinator.restoreOffset(
            fraction: 1.0,
            contentHeight: content,
            viewportHeight: viewport,
            topInset: 0,
            bottomInset: bottomInset
        )
        XCTAssertEqual(restored, content - viewport + bottomInset, accuracy: 0.001)
    }

    func testRestoreOffsetShortContentStaysAtTop() {
        // Content that fits within the viewport has no scroll range.
        let restored = TextView.Coordinator.restoreOffset(
            fraction: 0.9,
            contentHeight: 400,
            viewportHeight: 800,
            topInset: 50,
            bottomInset: 0
        )
        XCTAssertEqual(restored, -50, accuracy: 0.001)
    }
}
