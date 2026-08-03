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

    // MARK: - Shared resolution (BOTH readers)

    func testResolvedOffsetRejectsFirstOpen() {
        // Nothing saved yet — start at the top, don't "restore" to offset 0.
        XCTAssertNil(ReadingPosition.resolvedOffset(saved: 0, textLength: 5000))
    }

    func testResolvedOffsetRejectsPositionPastShrunkenText() {
        // Re-extract returned a shorter article (e.g. a member-only preview):
        // the saved spot no longer exists, so start at the top.
        XCTAssertNil(ReadingPosition.resolvedOffset(saved: 4200, textLength: 900))
        XCTAssertNil(ReadingPosition.resolvedOffset(saved: 900, textLength: 900))
    }

    func testResolvedOffsetKeepsInRangePosition() {
        XCTAssertEqual(ReadingPosition.resolvedOffset(saved: 4200, textLength: 9000), 4200)
    }

    // MARK: - Block reader: offset → block

    /// Three blocks of 100 UTF-16 units each, joined by "\n\n" — the layout
    /// `ArticleBlocks.textBlockRangesByIndex` produces. Indices 1 and 3 are
    /// skipped the way image/divider blocks are.
    private let ranges: [Int: NSRange] = [
        0: NSRange(location: 0, length: 100),
        2: NSRange(location: 102, length: 100),
        4: NSRange(location: 204, length: 100),
    ]
    private let textLength = 304

    func testBlockTargetFindsContainingBlock() {
        let target = ReadingPosition.blockTarget(offset: 152, ranges: ranges, textLength: textLength)
        XCTAssertEqual(target?.index, 2)
        XCTAssertEqual(target?.fraction ?? 0, 0.5, accuracy: 0.001)
    }

    func testBlockTargetAtBlockStartHasZeroFraction() {
        let target = ReadingPosition.blockTarget(offset: 204, ranges: ranges, textLength: textLength)
        XCTAssertEqual(target?.index, 4)
        XCTAssertEqual(target?.fraction ?? -1, 0, accuracy: 0.001)
    }

    func testBlockTargetInParagraphGapResumesAtNextBlock() {
        // Offset 101 is the second "\n" between block 0 and block 2 — resume at
        // the start of the block that follows, not the tail of the read one.
        let target = ReadingPosition.blockTarget(offset: 101, ranges: ranges, textLength: textLength)
        XCTAssertEqual(target?.index, 2)
        XCTAssertEqual(target?.fraction ?? -1, 0, accuracy: 0.001)
    }

    func testBlockTargetFirstOpenStartsAtTop() {
        XCTAssertNil(ReadingPosition.blockTarget(offset: 0, ranges: ranges, textLength: textLength))
    }

    func testBlockTargetPastEndStartsAtTop() {
        // Article re-parsed shorter: refuse to guess, start at the top (the
        // plain reader's behaviour, shared).
        XCTAssertNil(ReadingPosition.blockTarget(offset: 900, ranges: ranges, textLength: textLength))
    }

    func testBlockTargetSurvivesReparseShift() {
        // Re-extract inserted ~30 units of new text ahead of the saved spot, so
        // the offset now points a bit earlier in the article. It must still
        // resolve to a real block (grace), not collapse to the top.
        let shifted: [Int: NSRange] = [
            0: NSRange(location: 0, length: 130),
            2: NSRange(location: 132, length: 100),
            4: NSRange(location: 234, length: 100),
        ]
        let target = ReadingPosition.blockTarget(offset: 152, ranges: shifted, textLength: 334)
        XCTAssertEqual(target?.index, 2)
    }

    func testBlockTargetWithNoTextBlocksStartsAtTop() {
        // A video card whose article is metadata-only: nothing to scroll to.
        XCTAssertNil(ReadingPosition.blockTarget(offset: 50, ranges: [:], textLength: 300))
    }

    // MARK: - Block reader: geometry → offset

    func testCharacterOffsetAtBlockTopIsBlockStart() {
        // The block sits exactly on the reading line — the restore's own
        // resting position — so the offset it persists is the block's start.
        // This is what makes reopen → reopen idempotent.
        let offset = ReadingPosition.characterOffset(
            in: NSRange(location: 102, length: 100),
            blockMinY: 80,
            blockHeight: 400,
            lineY: 80
        )
        XCTAssertEqual(offset, 102)
    }

    func testCharacterOffsetScalesWithinBlock() {
        // Half the block has scrolled past the reading line.
        let offset = ReadingPosition.characterOffset(
            in: NSRange(location: 102, length: 100),
            blockMinY: -120,
            blockHeight: 400,
            lineY: 80
        )
        XCTAssertEqual(offset, 152)
    }

    func testCharacterOffsetClampsToBlockEnd() {
        // The block has scrolled entirely above the line.
        let offset = ReadingPosition.characterOffset(
            in: NSRange(location: 102, length: 100),
            blockMinY: -900,
            blockHeight: 400,
            lineY: 80
        )
        XCTAssertEqual(offset, 202)
    }

    func testCharacterOffsetClampsBelowLine() {
        // Block starts below the line (first screen): nothing of it is read.
        let offset = ReadingPosition.characterOffset(
            in: NSRange(location: 102, length: 100),
            blockMinY: 300,
            blockHeight: 400,
            lineY: 80
        )
        XCTAssertEqual(offset, 102)
    }

    // MARK: - Block reader: anchor correction

    func testCorrectedAnchorAimsAtReadingLine() {
        // Top alignment (anchor 0) landed the block 59pt too high, under the
        // notch. Anchor moves by the error over (container - block).
        let corrected = ReadingPosition.correctedAnchorY(
            currentAnchorY: 0,
            observedMinY: 0,
            desiredMinY: 83,
            blockHeight: 200,
            containerHeight: 900
        )
        XCTAssertEqual(corrected ?? -1, 83.0 / 700.0, accuracy: 0.0001)
    }

    func testCorrectedAnchorIsExactForTheLinearRelation() {
        // Applying the correction reproduces the desired position: block top =
        // anchor * (container - block) + the scroll view's fixed inset.
        let container: CGFloat = 900
        let block: CGFloat = 300
        let inset: CGFloat = -12 // whatever constant the scroll view applies
        let firstAnchor: CGFloat = 0
        let observed = firstAnchor * (container - block) + inset
        let desired: CGFloat = 83
        let corrected = ReadingPosition.correctedAnchorY(
            currentAnchorY: firstAnchor,
            observedMinY: observed,
            desiredMinY: desired,
            blockHeight: block,
            containerHeight: container
        )
        let landed = (corrected ?? 0) * (container - block) + inset
        XCTAssertEqual(landed, desired, accuracy: 0.001)
    }

    func testCorrectedAnchorGivesUpOnBlocksTallerThanViewport() {
        XCTAssertNil(ReadingPosition.correctedAnchorY(
            currentAnchorY: 0,
            observedMinY: 0,
            desiredMinY: 83,
            blockHeight: 1200,
            containerHeight: 900
        ))
    }

    func testCorrectedAnchorStaysInUnitRange() {
        // A target near the article's end can't be pushed further down.
        let corrected = ReadingPosition.correctedAnchorY(
            currentAnchorY: 0.98,
            observedMinY: -400,
            desiredMinY: 83,
            blockHeight: 200,
            containerHeight: 900
        )
        XCTAssertEqual(corrected ?? -1, 1, accuracy: 0.0001)
    }
}
