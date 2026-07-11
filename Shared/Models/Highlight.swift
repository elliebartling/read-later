import Foundation
import SwiftData

// CloudKit rules apply: attributes optional or defaulted, relationships optional.
@Model
final class Highlight {
    var id: UUID = UUID()
    var article: Article?
    /// UTF-16 offset into Article.plainText where the highlight starts.
    /// UTF-16 (not Character) because offsets originate from
    /// UITextView.selectedRange, which is an NSRange.
    var startOffset: Int = 0
    /// UTF-16 offset into Article.plainText where the highlight ends (exclusive).
    var endOffset: Int = 0
    /// Verbatim selected text — used as a fuzzy re-anchor if plainText shifts (re-parse).
    var quotedText: String = ""
    var colorRaw: String = HighlightColor.yellow.rawValue
    var note: String?
    var createdAt: Date = Date.now
    /// Last successful write to the export destination (Obsidian folder). Nil = never exported.
    var exportedAt: Date?

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        article: Article,
        startOffset: Int,
        endOffset: Int,
        quotedText: String,
        color: HighlightColor = .yellow,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.article = article
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.quotedText = quotedText
        self.colorRaw = color.rawValue
        self.note = note
        self.createdAt = createdAt
    }
}
