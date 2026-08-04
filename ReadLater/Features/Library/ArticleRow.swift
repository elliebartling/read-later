import SwiftUI

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // BR1 / BR2 — the row's source identity: a tiled favicon, with the
            // source's monogram on its `Source.*` hue standing in when the
            // site ships none. Library and Search rows had no source mark at
            // all before wave 3; the site name alone made three adjacent rows
            // from three platforms read as one undifferentiated column.
            FaviconTile(article: article)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(article.readAt == nil ? Ink.primary : Ink.secondary)
                if let site = article.siteName ?? article.url?.host {
                    Text(site)
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                }
                HStack(spacing: 10) {
                    if article.isVideoArticle {
                        Label("Video", systemImage: "play.rectangle.fill")
                            .accessibilityLabel("Video")
                    }
                    if article.estimatedReadingMinutes > 0 {
                        Label("\(article.estimatedReadingMinutes) min", systemImage: "clock")
                    }
                    if !article.allHighlights.isEmpty {
                        Label("\(article.allHighlights.count)", systemImage: "highlighter")
                    }
                    if article.parseStatus == .pending {
                        Label("Parsing…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    // **R7.** Failure is visible in the list. The one glyph I5
                    // permits in a meta line, because no text field carries
                    // that meaning — you should never learn about a failed
                    // parse by opening the article.
                    if article.parseStatus == .failed {
                        Label("Couldn't parse", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Semantic.warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(Ink.tertiary)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 0)
        }
        // Row vertical padding is the list's (§7.2), applied once via
        // `listRowInsets` — not doubled up here.
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
