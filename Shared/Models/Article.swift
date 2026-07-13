import Foundation
import SwiftData

// CloudKit-backed SwiftData requires every attribute to be optional or carry
// an inline default, and every relationship to be optional — otherwise
// ModelContainer creation throws at launch. Keep that invariant when adding
// properties to any synced model.
@Model
final class Article {
    var id: UUID = UUID()
    var url: URL?
    var title: String = ""
    var author: String?
    var siteName: String?
    var savedAt: Date = Date.now
    var readAt: Date?
    var isArchived: Bool = false
    var plainText: String = ""
    /// Raw extracted HTML (post-Readability). Used for optional in-app rendering
    /// with images. Never navigated as a live web page.
    var extractedHTML: String?
    var heroImageURL: URL?
    var estimatedReadingMinutes: Int = 0
    /// JSON-encoded [ArticleBlock]; nil until the article is (re)parsed by a
    /// blocks-aware parser. CloudKit-safe optional blob.
    var blocksJSON: Data?
    /// ArticleBlocks.currentVersion at encode time; 0 = no blocks.
    var blocksVersion: Int = 0
    /// Last reading position as a UTF-16 character index into `plainText` — the
    /// first character visible at the top of the viewport when the reader was
    /// last closed. Lets the reader resume at the same *word* rather than the
    /// same scroll percentage, so it survives font-size and column-width changes
    /// (the character doesn't move even though its pixel offset does). Uses the
    /// same offset space as highlight anchors.
    var readingCharacterOffset: Int = 0
    private var parseStatusRaw: Int = ParseStatus.pending.rawValue

    var parseStatus: ParseStatus {
        get { ParseStatus(rawValue: parseStatusRaw) ?? .pending }
        set { parseStatusRaw = newValue.rawValue }
    }

    var blocks: [ArticleBlock]? {
        guard let blocksJSON else { return nil }
        return ArticleBlocks.decode(blocksJSON)
    }

    func setBlocks(_ blocks: [ArticleBlock]) throws {
        blocksJSON = try JSONEncoder().encode(blocks)
        blocksVersion = ArticleBlocks.currentVersion
    }

    @Relationship(deleteRule: .nullify, inverse: \Tag.articles)
    var tags: [Tag]?

    @Relationship(deleteRule: .cascade, inverse: \Highlight.article)
    var highlights: [Highlight]?

    var allTags: [Tag] { tags ?? [] }
    var allHighlights: [Highlight] { highlights ?? [] }

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        author: String? = nil,
        siteName: String? = nil,
        savedAt: Date = .now,
        plainText: String = "",
        extractedHTML: String? = nil,
        heroImageURL: URL? = nil,
        estimatedReadingMinutes: Int = 0,
        parseStatus: ParseStatus = .pending
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.author = author
        self.siteName = siteName
        self.savedAt = savedAt
        self.isArchived = false
        self.plainText = plainText
        self.extractedHTML = extractedHTML
        self.heroImageURL = heroImageURL
        self.estimatedReadingMinutes = estimatedReadingMinutes
        self.parseStatusRaw = parseStatus.rawValue
    }

    enum ParseStatus: Int, Codable {
        case pending = 0
        case ready = 1
        case failed = 2
    }
}
