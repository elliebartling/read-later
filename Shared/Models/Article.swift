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
    /// Last reading position as a 0...1 scroll fraction (the visible bottom edge
    /// over total content height — same metric that drives read-tracking). Lets
    /// the reader restore the user's spot instead of jumping back to the top.
    /// Font/width changes don't invalidate it because it's a fraction, not an
    /// absolute offset.
    var readingProgress: Double = 0
    private var parseStatusRaw: Int = ParseStatus.pending.rawValue

    var parseStatus: ParseStatus {
        get { ParseStatus(rawValue: parseStatusRaw) ?? .pending }
        set { parseStatusRaw = newValue.rawValue }
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
