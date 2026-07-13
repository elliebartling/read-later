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

    // MARK: - Context disambiguation (v2)

    func testContextDisambiguatesRepeatedQuote() {
        // "cat" occurs 3×; the stale offset sits near the FIRST occurrence, so
        // step 3 (nearest) alone would pick it. Context must override and select
        // the second occurrence.
        let text = "the cat sat. the cat ran. the cat jumped."
        // Occurrences of "cat": 4, 17, 30. Stale offset near the first.
        let located = HighlightAnchor.locate(
            in: text,
            startOffset: 4,
            endOffset: 6, // [4,6) == "ca" ≠ "cat", so the fast path misses
            quotedText: "cat",
            prefixContext: "the ",
            suffixContext: " ran"
        )
        XCTAssertNotNil(located)
        // Both prefix ("the ") and suffix (" ran") match only the 2nd occurrence.
        XCTAssertEqual(located?.startOffset, 17)
        XCTAssertEqual(located?.wasRepaired, true)
    }

    func testContextBothMatchingBeatsOneMatching() {
        // prefix "the " matches all three; suffix " ran" only the 2nd. The
        // occurrence matching BOTH must win over those matching only one.
        let text = "the cat sat. the cat ran. the cat jumped."
        let located = HighlightAnchor.locate(
            in: text,
            startOffset: 99, // far from everything: proximity can't decide
            endOffset: 102,
            quotedText: "cat",
            prefixContext: "the ",
            suffixContext: " ran"
        )
        XCTAssertEqual(located?.startOffset, 17)
    }

    func testNearestMatchBeatsFirstMatchWithoutContext() {
        // No context. Stale offset is near the SECOND occurrence. The old code
        // returned the first match; the fix must return the nearest.
        let text = "the cat sat. the cat ran. the cat jumped."
        // [16,19) == " ca" (not "cat"), so the exact-offset fast path misses and
        // we fall through to nearest-occurrence selection.
        let located = HighlightAnchor.locate(
            in: text,
            startOffset: 16,
            endOffset: 19,
            quotedText: "cat"
        )
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.startOffset, 17) // nearest to 16, not the first (4)
        XCTAssertEqual(located?.wasRepaired, true)
    }

    // MARK: - contextAround capture helper

    func testContextAroundBasic() {
        let text = "Published Jan 1. The quick brown fox jumps over the lazy dog."
        // "quick brown" spans [21, 32).
        let (prefix, suffix) = HighlightAnchor.contextAround(
            range: NSRange(location: 21, length: 11),
            in: text
        )
        XCTAssertEqual(prefix?.hasSuffix("The ") ?? false, true)
        XCTAssertEqual(suffix?.hasPrefix(" fox") ?? false, true)
        XCTAssertLessThanOrEqual((prefix ?? "").utf16.count, 34)
        XCTAssertLessThanOrEqual((suffix ?? "").utf16.count, 34)
    }

    func testContextAroundNilAtBounds() {
        let text = "quick brown"
        let (prefix, suffix) = HighlightAnchor.contextAround(
            range: NSRange(location: 0, length: 11),
            in: text
        )
        XCTAssertNil(prefix)
        XCTAssertNil(suffix)
    }

    func testContextAroundEmojiBoundaryDoesNotSplitSurrogatePair() {
        // Build a prefix whose 32-unit window boundary lands INSIDE an emoji
        // (a surrogate pair). Expanding to composed-character boundaries must
        // keep the captured prefix a valid String, never a lone surrogate.
        //
        // Layout: 31 filler units, then "🎉" (2 UTF-16 units, at positions
        // 31–32), then the quote. The quote starts at 33; the 32-unit window
        // begins at 33 - 32 = 1, but we also test the tighter case where the
        // boundary bisects the emoji.
        let filler = String(repeating: "a", count: 31) // 31 units
        let text = filler + "🎉" + "QUOTE" + "🎈tail"
        let quoteLocation = (filler as NSString).length + ("🎉" as NSString).length // 33
        let quoteLength = ("QUOTE" as NSString).length // 5
        let (prefix, suffix) = HighlightAnchor.contextAround(
            range: NSRange(location: quoteLocation, length: quoteLength),
            in: text
        )
        // Prefix window [1, 33) starts mid-filler, but the emoji sits fully
        // inside it — still, assert validity and the surrogate-safe length bound.
        XCTAssertNotNil(prefix)
        XCTAssertLessThanOrEqual((prefix ?? "").utf16.count, 34)
        // Round-tripping the captured prefix through NSString/NSRange must not crash
        // and must preserve the emoji intact (no replacement char / lone surrogate).
        if let prefix {
            XCTAssertTrue(prefix.contains("🎉"))
            XCTAssertFalse(prefix.unicodeScalars.contains { $0 == "\u{FFFD}" })
            let ns = prefix as NSString
            _ = ns.substring(with: NSRange(location: 0, length: ns.length))
        }
        // Suffix begins with the trailing emoji, kept whole.
        XCTAssertNotNil(suffix)
        XCTAssertTrue(suffix?.contains("🎈") ?? false)
        XCTAssertLessThanOrEqual((suffix ?? "").utf16.count, 34)
    }

    func testContextAroundTightEmojiBoundarySplit() {
        // Here the 32-unit prefix window boundary bisects the emoji's surrogate
        // pair: quote at unit 34 means window start = 2, but place the emoji at
        // units 1–2 so the low surrogate is the first captured unit. Outward
        // expansion must pull in the high surrogate rather than emit a lone one.
        let head = "x" // 1 unit at index 0
        let emoji = "🎉" // units 1–2
        let mid = String(repeating: "b", count: 32) // units 3–34
        let text = head + emoji + mid + "QUOTE"
        let quoteLocation = (text as NSString).length - 5 // "QUOTE" length 5
        let (prefix, _) = HighlightAnchor.contextAround(
            range: NSRange(location: quoteLocation, length: 5),
            in: text
        )
        XCTAssertNotNil(prefix)
        // Whatever the boundary, the captured prefix is a well-formed String.
        XCTAssertFalse((prefix ?? "").unicodeScalars.contains { $0 == "\u{FFFD}" })
        XCTAssertLessThanOrEqual((prefix ?? "").utf16.count, 34)
    }

    // MARK: - Normalization pins (document current behavior; Phase 3 fuzzy matching)

    func testDecomposedQuoteAgainstNFCDocumentPinsCurrentBehavior() {
        // Document is NFC "café"; quotedText is decomposed "cafe\u{301}".
        // ACTUAL current behavior: NFC/decomposed differences are already
        // absorbed by Foundation's canonical matching — BOTH the fast path
        // (Swift `String ==`, canonical) and the re-anchor path
        // (NSString.range(of:), also canonical by default) treat the two forms
        // as equal. So the highlight anchors regardless of offset validity.
        // (Contrast the curly-vs-straight-quote pin below, which does NOT
        // resolve and awaits Phase 3 fuzzy matching.)
        let text = "I love this café a lot." // "café" spans [12,16)
        let decomposed = "cafe\u{301}"

        // Valid offsets → canonical fast-path match.
        let onOffset = HighlightAnchor.locate(
            in: text,
            startOffset: 12,
            endOffset: 16,
            quotedText: decomposed
        )
        XCTAssertNotNil(onOffset)
        XCTAssertEqual(onOffset?.wasRepaired, false)
        XCTAssertEqual(onOffset?.startOffset, 12)

        // Stale offsets → canonical re-anchor search still finds "café" at [12,16).
        let staleOffset = HighlightAnchor.locate(
            in: text,
            startOffset: 99,
            endOffset: 104,
            quotedText: decomposed
        )
        XCTAssertNotNil(staleOffset)
        XCTAssertEqual(staleOffset?.wasRepaired, true)
        XCTAssertEqual(staleOffset?.startOffset, 12)
    }

    func testCurlyVsStraightQuotePinsCurrentBehavior() {
        // Document uses a curly apostrophe; quotedText uses a straight one.
        // Verbatim matching treats them as distinct code points and the
        // whitespace fallback can't help (apostrophes aren't whitespace), so it
        // fails to anchor today. Pins reality pending Phase 3 fuzzy matching.
        let text = "It\u{2019}s a lovely day."
        let straight = "It's"
        let located = HighlightAnchor.locate(
            in: text,
            startOffset: 0,
            endOffset: 4,
            quotedText: straight
        )
        // ACTUAL current behavior: nil.
        XCTAssertNil(located)
    }
}
