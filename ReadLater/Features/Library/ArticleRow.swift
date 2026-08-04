import SwiftUI

/// A saved article as a `ReadableRow` (§8.1). Used by Library and Search, so
/// the same article renders identically in both — the audit found it rendering
/// with a chevron in one and without in the other.
///
/// Wave 2 moved every decision this view used to make locally into the shared
/// component: the unread signal (R1), the metadata grammar (R2), the source
/// string (R3) and the thumbnail slot (R4). What is left here is only the
/// mapping from `Article` to those slots.
struct ArticleRow: View {
    let article: Article

    var body: some View {
        ReadableRow(
            // R1 (amended) — an article is unread until it is opened, and the
            // row says so by *not* receding: full-ink title, full-strength
            // thumbnail. Read rows dim. No rail, no dot, no badge.
            isUnread: article.readAt == nil,
            title: article.title,
            summary: nil,
            metadata: metadata,
            // R4 — Library and Search can both contain thumbnails, so every
            // row reserves the slot even when the article has no hero image.
            reservesThumbnail: true,
            thumbnailURL: article.heroImageURL
        ) {
            // BR1 / BR2 — the row's source identity: a tiled favicon, with the
            // source's monogram on its `Source.*` hue standing in when the site
            // ships none.
            FaviconTile(article: article)
        }
    }

    /// **R2.** One `.caption` line, `" · "` joined, no glyphs, in the fixed
    /// order `source · relative date · duration/count`. The icon+label pairs
    /// this row used to print — `🕐 33 min`, `▶ Video`, `✏️ 2` — are exactly
    /// what I5 bans from a meta line: the text already carries the meaning.
    private var metadata: RowMetadata {
        var details: [String] = []
        if article.isVideoArticle { details.append("Video") }
        if article.estimatedReadingMinutes > 0 {
            details.append("\(article.estimatedReadingMinutes) min")
        }
        let highlights = article.allHighlights.count
        if highlights > 0 {
            details.append(highlights == 1 ? "1 highlight" : "\(highlights) highlights")
        }
        if article.parseStatus == .pending { details.append("Parsing…") }
        return RowMetadata(
            source: SourceIdentity.sourceString(for: article),
            date: article.savedAt,
            details: details,
            // R7 — failure is visible in the list; you never learn about it by
            // opening the article.
            isFailed: article.parseStatus == .failed
        )
    }
}
