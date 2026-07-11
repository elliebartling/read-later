import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var article: Article?
    /// Character offset into Article.plainText where the highlight starts.
    var startOffset: Int
    /// Character offset into Article.plainText where the highlight ends (exclusive).
    var endOffset: Int
    /// Verbatim selected text — used as a fuzzy re-anchor if plainText shifts (re-parse).
    var quotedText: String
    var colorRaw: String
    var note: String?
    var createdAt: Date
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
