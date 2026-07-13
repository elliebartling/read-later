import SwiftUI
import QuartzCore

/// The native block reader: a `ScrollView` of typed `ArticleBlock`s dispatched
/// to `TextBlockView` / `ImageBlockView` / `DividerBlockView`. It is the flagged
/// alternative to the TextKit `HighlightableTextView` (see `ReaderView`), sharing
/// the exact same highlight-callback family so both paths behave identically.
///
/// Offset discipline lives HERE, in one place: every highlight is located ONCE
/// against `plainText` (the global UTF-16 offset space) and then clipped into
/// per-block LOCAL ranges. `TextBlockView` never runs `HighlightAnchor` — it only
/// paints the local ranges this view hands it and reports GLOBAL offsets back via
/// the callbacks (it adds `baseOffset` itself).
struct BlockReaderView: View {

    let blocks: [ArticleBlock]
    /// The article's full plain text — the global offset space for highlights
    /// and the source `HighlightAnchor` locates against.
    let plainText: String
    let highlights: [Highlight]
    /// TTS paragraph index (into `ReaderView.paragraphs`) and whether read-aloud
    /// is active. Together they pick the spoken block to tint and follow.
    let currentParagraph: Int
    let isSpeaking: Bool

    let theme: ReaderTheme
    let fontSize: CGFloat
    let fontRaw: String
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let width: ReaderWidth
    let defaultColor: HighlightColor
    let editingHighlightID: UUID?

    // Same callback family as HighlightableTextView; ALL offsets are GLOBAL.
    let onCreateHighlight: (HighlightableTextView.HighlightIntent) -> UUID?
    let onUpdateHighlight: (UUID, NSRange, String) -> Void
    let onRecolorHighlight: (UUID, HighlightColor) -> Void
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    let onTapHighlight: (UUID) -> Void
    let onScrollProgress: (Double) -> Void
    /// Plain single tap in the body toggles the reader chrome.
    let onTap: () -> Void

    /// Cached per-block layout (base offsets, list markers, located highlights,
    /// paragraph→block map). Recomputed only when its signature changes — never
    /// every body pass. Held as a reference in @State so it survives the struct
    /// re-inits SwiftUI performs on each parent update.
    @State private var layout = BlockLayoutCache()

    /// Scroll phase bookkeeping so a tap that merely interrupts a scroll doesn't
    /// toggle chrome (mirrors HighlightableTextView's cooldown).
    @State private var isScrolling = false
    @State private var lastScrollTime: CFTimeInterval = 0
    private let scrollTapCooldown: CFTimeInterval = 0.25

    var body: some View {
        // Refresh the memo before anything reads it. This is a pure cache update
        // (no SwiftUI state is published), so it's safe inside body.
        let _ = layout.update(blocks: blocks, plainText: plainText, highlights: highlights)

        GeometryReader { geo in
            let contentWidth = max(1, geo.size.width - width.horizontalInset * 2)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { pair in
                            blockView(index: pair.offset, block: pair.element, contentWidth: contentWidth)
                                .id(pair.element.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, width.horizontalInset)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .onScrollGeometryChange(for: Double.self) { geometry in
                    let total = geometry.contentSize.height
                    guard total > 0 else { return 0 }
                    let bottom = geometry.contentOffset.y + geometry.containerSize.height
                    return min(1, max(0, bottom / total))
                } action: { _, progress in
                    onScrollProgress(progress)
                }
                .onScrollPhaseChange { _, newPhase, _ in
                    isScrolling = newPhase == .tracking
                        || newPhase == .interacting
                        || newPhase == .decelerating
                    lastScrollTime = CACurrentMediaTime()
                }
                // Follow the spoken block as TTS advances, but never fight the
                // user: only auto-scroll while they aren't driving the scroll.
                .onChange(of: spokenBlockID) { _, id in
                    guard isSpeaking, !isScrolling, let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: nil) }
                }
                // Opening the edit sheet: bring the owning block into view so the
                // selection handles aren't stranded off-screen behind the sheet.
                .onChange(of: editingHighlightID) { _, id in
                    guard let id, let blockID = blockID(owning: id) else { return }
                    withAnimation { proxy.scrollTo(blockID, anchor: nil) }
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(index: Int, block: ArticleBlock, contentWidth: CGFloat) -> some View {
        switch block.type {
        case .image:
            ImageBlockView(block: block, containerWidth: contentWidth, theme: theme)
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }
        case .divider:
            DividerBlockView(theme: theme)
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }
        default:
            if let range = layout.rangesByIndex[index] {
                TextBlockView(
                    block: block,
                    baseOffset: range.location,
                    listMarker: layout.markersByIndex[index],
                    locatedRanges: layout.locatedByIndex[index] ?? [],
                    isSpoken: isSpeaking && spokenBlockIndex == index,
                    theme: theme,
                    fontSize: fontSize,
                    fontRaw: fontRaw,
                    lineSpacing: lineSpacing,
                    defaultColor: defaultColor,
                    editingHighlightID: editingHighlightID,
                    onCreateHighlight: onCreateHighlight,
                    onUpdateHighlight: onUpdateHighlight,
                    onRecolorHighlight: onRecolorHighlight,
                    onDeleteHighlight: onDeleteHighlight,
                    onRequestNote: onRequestNote,
                    onTapHighlight: onTapHighlight,
                    onTap: handleTap
                )
            }
            // A text-bearing block with empty text contributes nothing to
            // plainText (no base offset) — skip it, matching derivePlainText.
        }
    }

    /// The block index currently spoken by TTS, or nil when idle / out of range.
    private var spokenBlockIndex: Int? {
        guard isSpeaking,
              currentParagraph >= 0,
              currentParagraph < layout.paragraphBlock.count else { return nil }
        return layout.paragraphBlock[currentParagraph]
    }

    private var spokenBlockID: UUID? {
        guard let index = spokenBlockIndex, blocks.indices.contains(index) else { return nil }
        return blocks[index].id
    }

    /// The id of the block whose located highlights include `highlightID`.
    private func blockID(owning highlightID: UUID) -> UUID? {
        for (index, located) in layout.locatedByIndex
        where located.contains(where: { $0.id == highlightID }) {
            if blocks.indices.contains(index) { return blocks[index].id }
        }
        return nil
    }

    /// Toggle chrome, unless the tap is really the tail end of a scroll.
    private func handleTap() {
        guard !isScrolling,
              CACurrentMediaTime() - lastScrollTime >= scrollTapCooldown else { return }
        onTap()
    }
}

/// Reference-type memo for the block reader's derived layout. Recomputes only
/// when `blocks`, `plainText`, or the highlight set changes — keyed by a cheap
/// signature so `body` passes triggered by scrolling / chrome toggles don't
/// re-run `HighlightAnchor` for every highlight.
final class BlockLayoutCache {
    private var signature = ""

    /// Global range of each text-bearing block, keyed by block index.
    private(set) var rangesByIndex: [Int: NSRange] = [:]
    /// Leading list marker per block index (only `.listItem` blocks).
    private(set) var markersByIndex: [Int: String] = [:]
    /// TTS paragraph index → block index.
    private(set) var paragraphBlock: [Int] = []
    /// Highlights clipped to LOCAL ranges, keyed by block index.
    private(set) var locatedByIndex: [Int: [TextBlockView.LocatedHighlight]] = [:]

    func update(blocks: [ArticleBlock], plainText: String, highlights: [Highlight]) {
        let sig = Self.signature(blocks: blocks, plainText: plainText, highlights: highlights)
        guard sig != signature else { return }
        signature = sig

        let ranges = ArticleBlocks.textBlockRangesByIndex(blocks)
        rangesByIndex = ranges
        markersByIndex = ArticleBlocks.listMarkers(blocks)
        paragraphBlock = ArticleBlocks.paragraphBlockIndices(blocks)
        locatedByIndex = Self.located(ranges: ranges, plainText: plainText, highlights: highlights)
    }

    /// Locate every highlight once against `plainText`, then clip its global
    /// range into each overlapping block as a LOCAL range.
    private static func located(
        ranges: [Int: NSRange],
        plainText: String,
        highlights: [Highlight]
    ) -> [Int: [TextBlockView.LocatedHighlight]] {
        guard !ranges.isEmpty else { return [:] }
        var result: [Int: [TextBlockView.LocatedHighlight]] = [:]
        for h in highlights {
            guard let located = HighlightAnchor.locate(
                in: plainText,
                startOffset: h.startOffset,
                endOffset: h.endOffset,
                quotedText: h.quotedText,
                prefixContext: h.prefixContext,
                suffixContext: h.suffixContext
            ) else { continue }
            let global = NSRange(
                location: located.startOffset,
                length: located.endOffset - located.startOffset
            )
            for (index, blockRange) in ranges {
                guard let local = ArticleBlocks.clipHighlight(global: global, toBlock: blockRange) else { continue }
                result[index, default: []].append(
                    TextBlockView.LocatedHighlight(id: h.id, color: h.color, range: local)
                )
            }
        }
        return result
    }

    private static func signature(
        blocks: [ArticleBlock],
        plainText: String,
        highlights: [Highlight]
    ) -> String {
        // plainText length + block count key the block-derived arrays (both
        // change on re-extract / structural edits); the per-highlight tuple keys
        // add/move/recolor/delete. Cheap to build, unlike re-locating.
        let highlightSig = highlights
            .map { "\($0.id.uuidString):\($0.startOffset):\($0.endOffset):\($0.colorRaw)" }
            .joined(separator: "|")
        return "\(plainText.utf16.count)|\(blocks.count)|\(highlightSig)"
    }
}
