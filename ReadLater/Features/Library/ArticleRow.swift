import SwiftUI

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(article.readAt == nil ? .primary : .secondary)
                if let site = article.siteName ?? article.url?.host {
                    Text(site)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
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
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
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
