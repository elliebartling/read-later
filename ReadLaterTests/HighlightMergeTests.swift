import XCTest
@testable import ReadLater

final class HighlightMergeTests: XCTestCase {

    // Offsets:            0123456789...
    private let text = "The quick brown fox jumps over the lazy dog."

    private func existing(
        id: UUID = UUID(),
        _ start: Int,
        _ end: Int,
        note: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1000)
    ) -> HighlightMerge.Existing {
        HighlightMerge.Existing(id: id, startOffset: start, endOffset: end, note: note, createdAt: createdAt)
    }

    // MARK: - No merge

    func testDisjointSelectionDoesNotMerge() {
        // "quick" = [4,9); selection "lazy" = [35,39) — a clear gap.
        let plan = HighlightMerge.plan(newStart: 35, newEnd: 39, existing: [existing(4, 9)], plainText: text)
        XCTAssertFalse(plan.didMerge)
        XCTAssertTrue(plan.absorbed.isEmpty)
        XCTAssertEqual(plan.unionStart, 35)
        XCTAssertEqual(plan.unionEnd, 39)
        XCTAssertEqual(plan.quotedText, "lazy")
        XCTAssertNil(plan.absorbedNote)
        XCTAssertNil(plan.earliestCreatedAt)
    }

    func testOneUnitGapDoesNotMerge() {
        // Existing [4,9) "quick"; selection [10,15) "brown" — the space at 9
        // separates them, so they neither overlap nor touch.
        let plan = HighlightMerge.plan(newStart: 10, newEnd: 15, existing: [existing(4, 9)], plainText: text)
        XCTAssertFalse(plan.didMerge)
    }

    func testNoExistingHighlights() {
        let plan = HighlightMerge.plan(newStart: 4, newEnd: 9, existing: [], plainText: text)
        XCTAssertFalse(plan.didMerge)
        XCTAssertEqual(plan.quotedText, "quick")
    }

    // MARK: - Overlap left / right

    func testOverlapExtendingRight() {
        // Existing "quick" [4,9); new selection "ick brown" [6,15).
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 6, newEnd: 15, existing: [existing(id: id, 4, 9)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.absorbed, [id])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 15)
        XCTAssertEqual(plan.quotedText, "quick brown")
    }

    func testOverlapExtendingLeft() {
        // Existing "brown" [10,15); new selection "quick br" [4,12).
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 4, newEnd: 12, existing: [existing(id: id, 10, 15)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.absorbed, [id])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 15)
        XCTAssertEqual(plan.quotedText, "quick brown")
    }

    // MARK: - Containment

    func testNewSelectionInsideExistingHighlight() {
        // Existing "quick brown fox" [4,19); new selection "brown" [10,15).
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 10, newEnd: 15, existing: [existing(id: id, 4, 19)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.absorbed, [id])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 19)
        XCTAssertEqual(plan.quotedText, "quick brown fox")
    }

    func testNewSelectionContainsExistingHighlight() {
        // Existing "brown" [10,15); new selection "quick brown fox" [4,19).
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 4, newEnd: 19, existing: [existing(id: id, 10, 15)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.absorbed, [id])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 19)
        XCTAssertEqual(plan.quotedText, "quick brown fox")
    }

    func testIdenticalRangeMerges() {
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 4, newEnd: 9, existing: [existing(id: id, 4, 9)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.absorbed, [id])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 9)
        XCTAssertEqual(plan.quotedText, "quick")
    }

    // MARK: - Exact adjacency (touching endpoints)

    func testAdjacentOnRightMerges() {
        // Existing "quick" [4,9); selection " brown" [9,15) starts exactly
        // where the highlight ends — flush, so they fuse.
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 9, newEnd: 15, existing: [existing(id: id, 4, 9)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 15)
        XCTAssertEqual(plan.quotedText, "quick brown")
    }

    func testAdjacentOnLeftMerges() {
        // Existing " brown" [9,15); selection "quick" [4,9) ends exactly where
        // the highlight starts.
        let id = UUID()
        let plan = HighlightMerge.plan(newStart: 4, newEnd: 9, existing: [existing(id: id, 9, 15)], plainText: text)
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 15)
        XCTAssertEqual(plan.quotedText, "quick brown")
    }

    // MARK: - Multi-highlight absorption

    func testSelectionBridgingTwoHighlightsAbsorbsBoth() {
        // "quick" [4,9) and "fox" [16,19); selection "brown " [9,16) bridges them.
        let a = UUID(), b = UUID()
        let plan = HighlightMerge.plan(
            newStart: 9, newEnd: 16,
            existing: [existing(id: a, 4, 9), existing(id: b, 16, 19)],
            plainText: text
        )
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(Set(plan.absorbed), [a, b])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 19)
        XCTAssertEqual(plan.quotedText, "quick brown fox")
    }

    func testChainedAbsorptionReachesFixedPoint() {
        // Selection overlaps only highlight A; absorbing A extends the union
        // until it touches B, which extends it to touch C. All three fold in.
        let a = UUID(), b = UUID(), c = UUID()
        let plan = HighlightMerge.plan(
            newStart: 4, newEnd: 6,
            existing: [
                existing(id: c, 15, 19), // " fox" — touches B's end
                existing(id: a, 5, 10), // "uick " — overlaps selection
                existing(id: b, 10, 15), // "brown" — touches A's end
            ],
            plainText: text
        )
        XCTAssertEqual(Set(plan.absorbed), [a, b, c])
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 19)
        XCTAssertEqual(plan.quotedText, "quick brown fox")
        // Absorbed ids come back in document order regardless of input order.
        XCTAssertEqual(plan.absorbed, [a, b, c])
    }

    func testUnrelatedHighlightIsNotDraggedIn() {
        let a = UUID(), far = UUID()
        let plan = HighlightMerge.plan(
            newStart: 6, newEnd: 12,
            existing: [existing(id: a, 4, 9), existing(id: far, 35, 39)],
            plainText: text
        )
        XCTAssertEqual(plan.absorbed, [a])
        XCTAssertEqual(plan.unionEnd, 12)
    }

    // MARK: - UTF-16 (emoji-bearing text)

    func testUnionOffsetsAndQuoteAreUTF16InEmojiText() {
        // "🎉🎉 The " = 2+2+1+3+1 = 9 UTF-16 units ("🎉" is a surrogate pair).
        // A Character-based interpretation would place "quick" at offset 7.
        let emojiText = "🎉🎉 The quick brown fox jumps."
        let id = UUID()
        // Existing "quick" [9,14); selection "ck brown" [11,20).
        let plan = HighlightMerge.plan(
            newStart: 11, newEnd: 20,
            existing: [existing(id: id, 9, 14)],
            plainText: emojiText
        )
        XCTAssertTrue(plan.didMerge)
        XCTAssertEqual(plan.unionStart, 9)
        XCTAssertEqual(plan.unionEnd, 20)
        XCTAssertEqual(plan.quotedText, "quick brown")
    }

    func testUnionSpanningEmojiRederivesQuoteVerbatim() {
        // Emoji INSIDE the union: the re-derived quote must contain it intact.
        // "Cats 🐈 purr loudly."  — "🐈" is 2 UTF-16 units at [5,7).
        let emojiText = "Cats 🐈 purr loudly."
        let id = UUID()
        // Existing "Cats" [0,4); selection " 🐈 purr" [4,12) overlaps-adjacent.
        let plan = HighlightMerge.plan(
            newStart: 4, newEnd: 12,
            existing: [existing(id: id, 0, 4)],
            plainText: emojiText
        )
        XCTAssertEqual(plan.unionStart, 0)
        XCTAssertEqual(plan.unionEnd, 12)
        XCTAssertEqual(plan.quotedText, "Cats 🐈 purr")
    }

    // MARK: - Note preservation

    func testSingleAbsorbedNoteSurvives() {
        let plan = HighlightMerge.plan(
            newStart: 6, newEnd: 15,
            existing: [existing(4, 9, note: "love this phrase")],
            plainText: text
        )
        XCTAssertEqual(plan.absorbedNote, "love this phrase")
    }

    func testMultipleNotesJoinInDocumentOrder() {
        let plan = HighlightMerge.plan(
            newStart: 9, newEnd: 16,
            existing: [
                existing(16, 19, note: "second note"),
                existing(4, 9, note: "first note"),
            ],
            plainText: text
        )
        XCTAssertEqual(plan.absorbedNote, "first note\n\nsecond note")
    }

    func testBlankAndNilNotesAreDropped() {
        let plan = HighlightMerge.plan(
            newStart: 4, newEnd: 19,
            existing: [
                existing(4, 9, note: "   "),
                existing(10, 15, note: nil),
                existing(16, 19, note: "kept"),
            ],
            plainText: text
        )
        XCTAssertEqual(plan.absorbedNote, "kept")
    }

    func testAllNotesBlankYieldsNil() {
        let plan = HighlightMerge.plan(
            newStart: 4, newEnd: 19,
            existing: [existing(4, 9, note: ""), existing(10, 15)],
            plainText: text
        )
        XCTAssertNil(plan.absorbedNote)
    }

    func testCombineNotesJoinsSurvivorAndAbsorbed() {
        XCTAssertEqual(
            HighlightMerge.combineNotes("mine", "theirs"),
            "mine\n\ntheirs"
        )
        XCTAssertEqual(HighlightMerge.combineNotes("mine", nil), "mine")
        XCTAssertEqual(HighlightMerge.combineNotes(nil, "theirs"), "theirs")
        XCTAssertEqual(HighlightMerge.combineNotes("  ", nil), nil)
        XCTAssertNil(HighlightMerge.combineNotes(nil, nil))
    }

    // MARK: - createdAt

    func testEarliestCreatedAtIsReported() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 5000)
        let plan = HighlightMerge.plan(
            newStart: 4, newEnd: 19,
            existing: [
                existing(4, 9, createdAt: late),
                existing(10, 15, createdAt: early),
            ],
            plainText: text
        )
        XCTAssertEqual(plan.earliestCreatedAt, early)
    }

    // MARK: - Robustness

    func testSelectionClampedToTextBounds() {
        let plan = HighlightMerge.plan(newStart: 40, newEnd: 999, existing: [], plainText: text)
        XCTAssertEqual(plan.unionEnd, (text as NSString).length)
        XCTAssertEqual(plan.quotedText, "dog.")
    }

    func testInvertedSelectionIsNormalised() {
        let plan = HighlightMerge.plan(newStart: 9, newEnd: 4, existing: [], plainText: text)
        XCTAssertEqual(plan.unionStart, 4)
        XCTAssertEqual(plan.unionEnd, 9)
        XCTAssertEqual(plan.quotedText, "quick")
    }

    // MARK: - Session color (edit-menu checkmark after create/merge)

    func testSessionColorUsesSurvivorColorOnMerge() {
        // createHighlight merged into an existing highlight and returned its
        // ID — the checkmark must show the survivor's kept color.
        let survivor = UUID()
        let color = HighlightMerge.sessionColor(
            forCreated: survivor,
            existing: [(id: UUID(), color: .yellow), (id: survivor, color: .blue)],
            defaultColor: .yellow
        )
        XCTAssertEqual(color, .blue)
    }

    func testSessionColorUsesDefaultForFreshHighlight() {
        // A brand-new highlight isn't among the pre-existing ones — it was
        // created with the default color, so the checkmark shows that.
        let color = HighlightMerge.sessionColor(
            forCreated: UUID(),
            existing: [(id: UUID(), color: .blue)],
            defaultColor: .green
        )
        XCTAssertEqual(color, .green)
    }

    func testSessionColorWithNoExistingHighlights() {
        let color = HighlightMerge.sessionColor(
            forCreated: UUID(),
            existing: [],
            defaultColor: .pink
        )
        XCTAssertEqual(color, .pink)
    }
}
