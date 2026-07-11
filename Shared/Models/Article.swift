import Foundation
import SwiftData

@Model
final class Article {
    var id: UUID
    var url: URL
    var title: String
    var author: String?
    var siteName: String?
    var savedAt: Date
    var readAt: Date?
    var isArchived: Bool
    var plainText: String
    /// Raw extracted HTML (post-Readability). Used for optional in-app rendering
    /// with images. Never navigated as a live web page.
    var extractedHTML: String?
    var heroImageURL: URL?
    var estimatedReadingMinutes: Int
    var parseStatus: ParseStatus

    @Relationship(deleteRule: .nullify, inverse: \Tag.articles)
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \Highlight.article)
    var highlights: [Highlight] = []

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
        self.parseStatus = parseStatus
    }

    enum ParseStatus: Int, Codable {
        case pending = 0
        case ready = 1
        case failed = 2
    }
}
