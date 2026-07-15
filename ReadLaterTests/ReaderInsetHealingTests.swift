import UIKit
import XCTest
@testable import ReadLater

/// Pins the reader-inset math and the per-layout-pass healing that keeps the
/// article's horizontal margins stable through TTS, chrome/audio-bar
/// transitions, and safe-area changes.
///
/// Regression context: on device, `textContainerInset` was observed collapsing
/// to zero during TTS playback (text flush against the screen edge, spoken-
/// paragraph tint full-bleed). The reset itself comes from UIKit (a TextKit 1
/// compatibility fallback swaps the text container; bar transitions can also
/// reset container state), but it was STICKY because insets were only applied
/// on safe-area changes. Both readers now re-assert their insets in
/// `layoutSubviews`, so any external reset heals on the next pass.
final class ReaderInsetHealingTests: XCTestCase {

    // MARK: - Pure inset math (frozenReaderInsets)

    private let base = UIEdgeInsets(top: 24, left: 32, bottom: 40, right: 32)

    func testHorizontalInsetsAlwaysComeFromBase() {
        // Whatever the safe area does, left/right must be exactly the base
        // reading margins — the safe area never moves the text horizontally.
        for (top, bottom) in [(CGFloat(0), CGFloat(0)), (59, 34), (103, 34)] {
            let result = ReaderTextView.frozenReaderInsets(
                base: base, safeAreaTop: top, safeAreaBottom: bottom, frozenTop: nil
            )
            XCTAssertEqual(result.insets.left, 32)
            XCTAssertEqual(result.insets.right, 32)
        }
    }

    func testTopFreezesAtImmersiveMinimum() {
        // First layout with chrome hidden: island top (59) freezes.
        let first = ReaderTextView.frozenReaderInsets(
            base: base, safeAreaTop: 59, safeAreaBottom: 34, frozenTop: nil
        )
        XCTAssertEqual(first.frozenTop, 59)
        XCTAssertEqual(first.insets.top, 24 + 59)

        // Chrome revealed: safe area grows to 103, but the frozen value wins —
        // the article must not shift down under the translucent bar.
        let revealed = ReaderTextView.frozenReaderInsets(
            base: base, safeAreaTop: 103, safeAreaBottom: 34, frozenTop: first.frozenTop
        )
        XCTAssertEqual(revealed.frozenTop, 59)
        XCTAssertEqual(revealed.insets.top, 24 + 59)
    }

    func testTransientZeroTopDoesNotUnfreezeOrShift() {
        // Mid-transition (or briefly detached) the safe area can report 0.
        // The frozen top must survive and keep padding the text.
        let result = ReaderTextView.frozenReaderInsets(
            base: base, safeAreaTop: 0, safeAreaBottom: 0, frozenTop: 59
        )
        XCTAssertEqual(result.frozenTop, 59)
        XCTAssertEqual(result.insets.top, 24 + 59)
    }

    func testBottomFollowsLiveSafeArea() {
        let a = ReaderTextView.frozenReaderInsets(
            base: base, safeAreaTop: 59, safeAreaBottom: 34, frozenTop: 59
        )
        XCTAssertEqual(a.insets.bottom, 40 + 34)
        let b = ReaderTextView.frozenReaderInsets(
            base: base, safeAreaTop: 59, safeAreaBottom: 0, frozenTop: 59
        )
        XCTAssertEqual(b.insets.bottom, 40)
    }

    func testFrozenTopTakesSmallerLaterValue() {
        // If a smaller positive top shows up later (e.g. status bar hidden),
        // the freeze tightens to the new immersive minimum.
        let result = ReaderTextView.frozenReaderInsets(
            base: base, safeAreaTop: 20, safeAreaBottom: 0, frozenTop: 59
        )
        XCTAssertEqual(result.frozenTop, 20)
        XCTAssertEqual(result.insets.top, 24 + 20)
    }

    // MARK: - Plain reader: layout pass heals an external inset reset

    @MainActor
    func testReaderTextViewHealsExternalInsetResetOnLayout() {
        let tv = ReaderTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        tv.contentInsetAdjustmentBehavior = .never
        tv.baseTextInsets = base
        tv.textContainer.lineFragmentPadding = 0
        tv.text = "Some article text"
        tv.layoutIfNeeded()
        let healthy = tv.textContainerInset
        XCTAssertEqual(healthy.left, 32)
        XCTAssertEqual(healthy.right, 32)

        // Simulate UIKit resetting the container behind our back (the TextKit 1
        // fallback / bar-transition failure seen on device).
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 5

        // The next layout pass must restore the reading margins.
        tv.setNeedsLayout()
        tv.layoutIfNeeded()
        XCTAssertEqual(tv.textContainerInset, healthy,
                       "layout pass must re-assert the reader insets")
        XCTAssertEqual(tv.textContainer.lineFragmentPadding, 0)
    }

    @MainActor
    func testReaderTextViewKeepsInsetsThroughSpokenRangeStyleChurn() {
        // TTS advances re-set attributedText each paragraph; insets must hold.
        let tv = ReaderTextView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        tv.contentInsetAdjustmentBehavior = .never
        tv.baseTextInsets = base
        tv.textContainer.lineFragmentPadding = 0

        let text = "Paragraph one.\n\nParagraph two.\n\nParagraph three."
        for spokenStart in [0, 16, 33] {
            let str = NSMutableAttributedString(string: text)
            str.addAttribute(
                .backgroundColor,
                value: UIColor.systemYellow.withAlphaComponent(0.16),
                range: NSRange(location: spokenStart, length: 10)
            )
            tv.attributedText = str
            tv.setNeedsLayout()
            tv.layoutIfNeeded()
            XCTAssertEqual(tv.textContainerInset.left, 32)
            XCTAssertEqual(tv.textContainerInset.right, 32)
            XCTAssertEqual(tv.textContainer.lineFragmentPadding, 0)
        }
    }

    // MARK: - Block reader: layout pass heals an external inset reset

    @MainActor
    func testBlockTextViewHealsExternalInsetResetOnLayout() {
        let tv = BlockTextView(frame: CGRect(x: 0, y: 0, width: 326, height: 100))
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.text = "A block of text"
        tv.layoutIfNeeded()

        // Simulate the same external container reset: UIKit's defaults are a
        // nonzero inset and 5pt line-fragment padding.
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        tv.textContainer.lineFragmentPadding = 5

        tv.setNeedsLayout()
        tv.layoutIfNeeded()
        XCTAssertEqual(tv.textContainerInset, .zero,
                       "block text views own no insets — margins are SwiftUI padding")
        XCTAssertEqual(tv.textContainer.lineFragmentPadding, 0)
    }
}
