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
}
