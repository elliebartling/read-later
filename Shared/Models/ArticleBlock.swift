import Foundation

/// Typed reader blocks parsed from Readability HTML. `blocksJSON` on Article
/// stores `[ArticleBlock]` encoded as JSON (schema versioned by blocksVersion).
struct ArticleBlock: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: BlockType
    var text: String? = nil
    var level: Int? = nil
    var src: URL? = nil
    var alt: String? = nil
    var width: Int? = nil
    var height: Int? = nil
    var listStyle: ListStyle? = nil
    /// True when a `.listItem`'s leading marker ("• " / "3. ") is already baked
    /// into `text` at parse time — the route that lets the PLAIN reader (which
    /// shows only `derivePlainText`) render list structure. The block reader
    /// keys off this to skip its own SwiftUI-composed marker so it never
    /// double-marks. Additive & optional so it is CloudKit-safe: older decoders
    /// ignore the unknown JSON key, and blocks parsed before this shipped decode
    /// as `nil` (their markers stay composed at render time, unchanged).
    var markerBaked: Bool? = nil
    /// True when the block's text came from inside a `<blockquote>`. Set at
    /// parse time on EVERY block the quote contains — a multi-paragraph quote
    /// yields several flagged blocks, and a quoted list item stays a
    /// `.listItem` that is also quoted — so quote membership is orthogonal to
    /// block type and no new `BlockType` case is needed. (A new enum case would
    /// be a cross-version hazard: an older device decoding an unknown `type`
    /// string drops the block, see docs/youtube-save-design.md.) Additive and
    /// optional, so it is CloudKit-safe the same way `markerBaked` is: older
    /// decoders ignore the unknown JSON key and blocks parsed before this
    /// shipped decode as `nil`.
    var isQuote: Bool? = nil

    /// Whether this block should render as quoted. Reads the additive flag and
    /// falls back to the legacy `.blockquote` type, so blocks stored before
    /// `isQuote` existed (leaf `<blockquote>`s, which were the only quotes the
    /// walker recognised) keep their quote treatment.
    var isQuoted: Bool { isQuote == true || type == .blockquote }
}

enum BlockType: String, Codable {
    case paragraph, heading, listItem, blockquote, preformatted, caption
    case image, divider

    /// Whether this block's text participates in `plainText` (the highlight
    /// offset space) and TTS.
    var isTextBearing: Bool {
        switch self {
        case .paragraph, .heading, .listItem, .blockquote, .preformatted, .caption:
            return true
        case .image, .divider:
            return false
        }
    }
}

enum ListStyle: String, Codable { case ordered, unordered }

enum ArticleBlocks {
    static let currentVersion = 1

    /// Canonical rule: plainText = text-bearing blocks joined "\n\n".
    /// MUST stay byte-compatible with the parser's legacy join.
    static func derivePlainText(_ blocks: [ArticleBlock]) -> String {
        blocks.compactMap { $0.type.isTextBearing ? $0.text : nil }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// UTF-16 offset of each text-bearing block's start within derivePlainText.
    /// Block-local selection → global offset = base + local (both UTF-16).
    static func textBlockBaseOffsets(_ blocks: [ArticleBlock]) -> [Int] {
        var offsets: [Int] = []
        var cursor = 0
        for b in blocks where b.type.isTextBearing {
            guard let t = b.text, !t.isEmpty else { continue }
            offsets.append(cursor)
            cursor += t.utf16.count + 2 // "\n\n"
        }
        return offsets
    }

    static func decode(_ data: Data) -> [ArticleBlock]? {
        try? JSONDecoder().decode([ArticleBlock].self, from: data)
    }

    // MARK: - Block reader layout (pure, used by BlockReaderView)

    /// Global UTF-16 range of each text-bearing, non-empty block within
    /// `derivePlainText`, keyed by the block's index in `blocks`. Non-text and
    /// empty-text blocks are absent from the result (they contribute nothing to
    /// `plainText`, so they have no offset). The `location` of each range is the
    /// block's base offset; `length` is its UTF-16 text length.
    static func textBlockRangesByIndex(_ blocks: [ArticleBlock]) -> [Int: NSRange] {
        var result: [Int: NSRange] = [:]
        var cursor = 0
        for (i, b) in blocks.enumerated() where b.type.isTextBearing {
            guard let t = b.text, !t.isEmpty else { continue }
            let len = (t as NSString).length
            result[i] = NSRange(location: cursor, length: len)
            cursor += len + 2 // "\n\n"
        }
        return result
    }

    /// GLOBAL UTF-16 ranges of every quoted block within `plainText` — the
    /// PLAIN reader's route to quote styling, since it renders `plainText`
    /// alone and has no per-block views.
    ///
    /// Each candidate range is verified to actually hold that block's text
    /// before it is returned. `plainText` is stored on the article and blocks
    /// are decoded from a separate blob; for anything parsed before the block
    /// pipeline (or by the legacy text join) the two can disagree, and styling
    /// an unverified range would tint the wrong paragraph. Verification makes a
    /// drifted pair degrade to "no quote styling" instead of mis-styling.
    ///
    /// Purely presentational: the text is never mutated, so the UTF-16
    /// highlight offset space is untouched.
    static func quoteRanges(_ blocks: [ArticleBlock], in plainText: String) -> [NSRange] {
        let ns = plainText as NSString
        var result: [NSRange] = []
        var cursor = 0
        for b in blocks where b.type.isTextBearing {
            guard let t = b.text, !t.isEmpty else { continue }
            let len = (t as NSString).length
            defer { cursor += len + 2 } // "\n\n"
            guard b.isQuoted else { continue }
            guard cursor >= 0, cursor + len <= ns.length else { continue }
            let range = NSRange(location: cursor, length: len)
            guard ns.substring(with: range) == t else { continue }
            result.append(range)
        }
        return result
    }

    /// Clips a GLOBAL highlight range to a single block's GLOBAL range and
    /// returns the overlap as a range LOCAL to that block (offsets shifted back
    /// by the block's base). Returns nil when the two ranges don't overlap.
    ///
    /// A legacy highlight that spans a paragraph break clips into partial ranges
    /// across several blocks; painting each partial range is correct. (Editing
    /// such a highlight from within one block clamps it to that block — an
    /// accepted v1 limitation, since the block only knows its own slice.)
    static func clipHighlight(global: NSRange, toBlock block: NSRange) -> NSRange? {
        let start = max(global.location, block.location)
        let end = min(global.location + global.length, block.location + block.length)
        guard end > start else { return nil }
        return NSRange(location: start - block.location, length: end - start)
    }

    /// Leading list markers keyed by block index, for blocks whose marker is
    /// NOT already baked into `text`. A run of consecutive `.listItem` blocks
    /// shares one numbering context; ordered items render "1.", "2.", … and
    /// reset at the start of each run, while unordered items render "•". Only
    /// ordered items advance the ordinal, so a run that mixes styles keeps
    /// ordered numbering contiguous.
    ///
    /// `.listItem` blocks with `markerBaked == true` are skipped entirely: their
    /// marker already lives in `text` (parse-time baking), so composing another
    /// here would double it. Such blocks are parsed with markers inline; the
    /// legacy render-time-marker path serves only pre-baking stored blocks.
    static func listMarkers(_ blocks: [ArticleBlock]) -> [Int: String] {
        var markers: [Int: String] = [:]
        var ordinal = 1
        var inRun = false
        for (i, b) in blocks.enumerated() {
            guard b.type == .listItem, b.markerBaked != true else {
                inRun = false
                continue
            }
            if !inRun {
                ordinal = 1
                inRun = true
            }
            if b.listStyle == .ordered {
                markers[i] = "\(ordinal)."
                ordinal += 1
            } else {
                markers[i] = "•"
            }
        }
        return markers
    }

    /// Maps each TTS paragraph index to the index of the block it belongs to.
    ///
    /// TTS paragraphs come from `plainText.components(separatedBy: "\n")` after
    /// trimming and dropping empties (see `ReaderView.paragraphs`). Because
    /// `derivePlainText` joins blocks with "\n\n" AND a block's own text may
    /// contain newlines (a multi-line `preformatted` block), one block can yield
    /// several paragraphs. Walking each block's text through the same split keeps
    /// the block-reader's spoken-block mapping exactly in step with that array.
    static func paragraphBlockIndices(_ blocks: [ArticleBlock]) -> [Int] {
        var result: [Int] = []
        for (i, b) in blocks.enumerated() where b.type.isTextBearing {
            guard let t = b.text, !t.isEmpty else { continue }
            let paragraphCount = t
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .count
            for _ in 0 ..< paragraphCount { result.append(i) }
        }
        return result
    }
}
