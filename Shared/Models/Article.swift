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
    /// True when the cruft filter removed anything on the most recent parse
    /// (docs/parser-cruft-design.md). Debug signal for now — inline default
    /// keeps the CloudKit invariant.
    var wasCruftFiltered: Bool = false
    /// JSON-encoded [ArticleBlock] the cruft filter removed on the most recent
    /// parse; nil when nothing was removed. Debug-inspection only today (a
    /// future "Show removed content" escape hatch can render these).
    /// CloudKit-safe optional blob.
    var removedCruftJSON: Data?
    /// True when the most recent parse likely captured a truncated member-only
    /// preview (see `PaywallDetector.verdict` — an in-DOM gate CTA, or
    /// schema.org `isAccessibleForFree:false` with sub-preview-scale content).
    /// This means "our capture is partial", NOT "the source is member-only":
    /// an authenticated re-extract that returns the full text clears it, even
    /// though the schema value stays false forever. Drives the reader's
    /// "preview only" banner. Inline default keeps the CloudKit invariant.
    /// Recomputed on every parse so it always describes the current text.
    var isPaywalledPartial: Bool = false
    /// Last reading position as a UTF-16 character index into `plainText` — the
    /// first character visible at the top of the viewport when the reader was
    /// last closed. Lets the reader resume at the same *word* rather than the
    /// same scroll percentage, so it survives font-size and column-width changes
    /// (the character doesn't move even though its pixel offset does). Uses the
    /// same offset space as highlight anchors.
    var readingCharacterOffset: Int = 0
    /// Optional link to a discussion thread this article came from — the Reddit
    /// comments permalink for articles saved from a Reddit feed entry. Named
    /// generically (not Reddit-specific) so other sources can reuse it. Drives
    /// the reader's "View discussion" affordance. CloudKit-safe optional.
    var discussionURL: URL?
    private var parseStatusRaw: Int = ParseStatus.pending.rawValue

    var parseStatus: ParseStatus {
        get { ParseStatus(rawValue: parseStatusRaw) ?? .pending }
        set { parseStatusRaw = newValue.rawValue }
    }

    var blocks: [ArticleBlock]? {
        guard let blocksJSON else { return nil }
        return ArticleBlocks.decode(blocksJSON)
    }

    /// Decoded view of `removedCruftJSON` for debugging; nil when the last
    /// parse removed nothing.
    var removedCruftBlocks: [ArticleBlock]? {
        guard let removedCruftJSON else { return nil }
        return ArticleBlocks.decode(removedCruftJSON)
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
