import CoreGraphics
import Foundation

/// Pure reading-position math, shared by BOTH readers.
///
/// `Article.readingCharacterOffset` stores the reading spot as a UTF-16 offset
/// into `plainText` — the same offset space highlights live in — so the two
/// readers persist and resume the *same* number and a reader switch keeps your
/// place. What differs is the geometry each one has to work with:
///
/// - The plain reader (`HighlightableTextView`) owns a single `UITextView`, so
///   it can turn the offset into caret geometry and scroll to the exact line
///   (`Coordinator.restoreOffsetY`).
/// - The block reader (`BlockReaderView`) is a `LazyVStack` of per-block text
///   views with no global text layout. It resolves the offset to the *block*
///   that contains it and scrolls that block's top to the reading line —
///   block granularity, with the intra-block position kept only as an
///   approximation (see `characterOffset(in:...)`).
///
/// Everything here is deliberately UIKit-free so both paths are unit-testable
/// (`ReadLaterTests/ReadingPositionTests.swift`). Keeping the shared rules in
/// one place is what stops the two readers drifting apart again (AGENTS.md,
/// "There are two readers").
enum ReadingPosition {

    /// A stored offset validated against the text as it exists *now*.
    ///
    /// Returns nil when there is nothing to restore — a first open (0), or a
    /// position past the end of the text because the article was re-extracted
    /// shorter since it was last read. Both mean "start at the top", which is
    /// the plain reader's long-standing behaviour; the block reader adopts it
    /// verbatim rather than inventing its own.
    ///
    /// A re-extract that merely *shifts* the text leaves the offset in range,
    /// so the reader lands near — not exactly at — the old spot. That grace is
    /// intentional: an approximate resume beats snapping back to the top.
    static func resolvedOffset(saved: Int, textLength: Int) -> Int? {
        guard saved > 0, saved < textLength else { return nil }
        return saved
    }

    /// Where a block-reader restore should land.
    struct BlockTarget: Equatable {
        /// Index into the reader's `blocks` array.
        let index: Int
        /// How far into that block the saved offset sat, 0...1. Recorded for
        /// diagnostics and future intra-block precision; v1 restores to the
        /// block's top regardless.
        let fraction: Double
    }

    /// Resolves a saved offset to the block that contains it.
    ///
    /// `ranges` is `ArticleBlocks.textBlockRangesByIndex` — the GLOBAL UTF-16
    /// range of every text-bearing block, keyed by block index. Non-text blocks
    /// (images, dividers) are absent, exactly as they are absent from
    /// `plainText`.
    ///
    /// Returns nil for "start at the top": nothing saved, a position past the
    /// end of the current text, a block-less article (a video card whose
    /// metadata is all there is), or an offset that lands before the first
    /// text block.
    static func blockTarget(offset saved: Int, ranges: [Int: NSRange], textLength: Int) -> BlockTarget? {
        guard let offset = resolvedOffset(saved: saved, textLength: textLength), !ranges.isEmpty else {
            return nil
        }
        let sorted = ranges.sorted { $0.value.location < $1.value.location }

        // The last block that starts at or before the offset.
        var candidate: (index: Int, range: NSRange)?
        for (index, range) in sorted {
            if range.location > offset { break }
            candidate = (index, range)
        }
        guard let candidate else { return nil }

        let end = candidate.range.location + candidate.range.length
        guard offset < end else {
            // The offset fell in the "\n\n" separator between blocks (or in a
            // block that shrank since it was saved). Resume at the START of the
            // next block rather than the tail of the one already read.
            if let next = sorted.first(where: { $0.value.location > offset }) {
                return BlockTarget(index: next.key, fraction: 0)
            }
            return BlockTarget(index: candidate.index, fraction: 1)
        }

        let fraction = candidate.range.length > 0
            ? Double(offset - candidate.range.location) / Double(candidate.range.length)
            : 0
        return BlockTarget(index: candidate.index, fraction: min(max(fraction, 0), 1))
    }

    /// The UTF-16 offset to persist for the topmost visible block.
    ///
    /// `lineY` is the reader's reading line — the y (in the scroll view's own
    /// coordinate space) where restored text is placed, i.e. the top of the
    /// readable area below the notch. The character is approximated by how far
    /// the block has scrolled past that line, in proportion to its height.
    /// That is a linear guess, not a layout query: it is exact at a block's
    /// top and bottom (the only positions a restore can produce) and drifts by
    /// at most a few lines in between, which is the accepted v1 granularity.
    static func characterOffset(
        in range: NSRange,
        blockMinY: CGFloat,
        blockHeight: CGFloat,
        lineY: CGFloat
    ) -> Int {
        guard blockHeight > 0 else { return range.location }
        let raw = Double((lineY - blockMinY) / blockHeight)
        let fraction = min(max(raw, 0), 1)
        let advance = min(Int((Double(range.length) * fraction).rounded()), range.length)
        return range.location + advance
    }

    /// The `scrollTo(_:anchor:)` anchor that brings an already-visible block's
    /// top to `desiredMinY`.
    ///
    /// SwiftUI aligns the *same* unit point in the target view and in the
    /// visible region, so the block's top lands at `anchor.y * (containerHeight
    /// - blockHeight)` plus whatever fixed inset the scroll view applies. That
    /// relation is linear in the anchor with slope `containerHeight -
    /// blockHeight`, so one measurement of where the block actually landed is
    /// enough to solve for the anchor that hits the mark — and because the
    /// correction is derived from an observation, it absorbs any constant
    /// content inset or lazily-settled height above the block.
    ///
    /// Returns nil when the block is as tall as (or taller than) the viewport:
    /// the relation degenerates and top alignment is the best available answer.
    static func correctedAnchorY(
        currentAnchorY: CGFloat,
        observedMinY: CGFloat,
        desiredMinY: CGFloat,
        blockHeight: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat? {
        let slope = containerHeight - blockHeight
        guard slope > 1 else { return nil }
        let corrected = currentAnchorY + (desiredMinY - observedMinY) / slope
        return min(max(corrected, 0), 1)
    }
}
