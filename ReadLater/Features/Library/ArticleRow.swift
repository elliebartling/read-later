import SwiftUI

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
