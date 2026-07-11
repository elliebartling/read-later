import Foundation

/// Renders an Article + its highlights as a single Obsidian-friendly markdown
/// note. Frontmatter first, then highlights as blockquotes, then a metadata
/// footer. Idempotent — writing the same article + highlight set produces the
/// same file bytes so a downstream file watcher doesn't churn.
enum MarkdownFormatter {

    struct RenderInput {
        let article: Article
        let highlights: [Highlight]
    }

    static func slug(for article: Article) -> String {
        let base = article.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let date = ISO8601DateFormatter.dayOnly.string(from: article.savedAt)
        return "\(date)-\(base.isEmpty ? article.id.uuidString : base)"
    }

    static func fileName(for article: Article) -> String {
        "\(slug(for: article)).md"
    }

    static func render(_ input: RenderInput) -> String {
        var out = ""
        out.append(frontmatter(for: input.article))
        out.append("\n\n# \(escapeMarkdown(input.article.title))\n\n")
        if let author = input.article.author {
            out.append("*by \(author)*\n\n")
        }
        out.append("[Original link](\(input.article.url.absoluteString))\n\n")
        if !input.highlights.isEmpty {
            out.append("## Highlights\n\n")
            let sorted = input.highlights.sorted { $0.startOffset < $1.startOffset }
            for h in sorted {
                let colorTag = "[[color::\(h.color.rawValue)]]"
                out.append("> \(escapeBlockquote(h.quotedText)) \(colorTag)\n")
                if let note = h.note, !note.isEmpty {
                    out.append(">\n> **Note:** \(escapeBlockquote(note))\n")
                }
                out.append("\n")
            }
        }
        return out
    }

    private static func frontmatter(for article: Article) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \(yamlString(article.title))")
        lines.append("url: \(yamlString(article.url.absoluteString))")
        if let a = article.author { lines.append("author: \(yamlString(a))") }
        if let s = article.siteName { lines.append("site: \(yamlString(s))") }
        lines.append("savedAt: \(ISO8601DateFormatter.iso8601.string(from: article.savedAt))")
        if let r = article.readAt { lines.append("readAt: \(ISO8601DateFormatter.iso8601.string(from: r))") }
        if !article.tags.isEmpty {
            let list = article.tags.map { "\"\($0.name)\"" }.joined(separator: ", ")
            lines.append("tags: [\(list)]")
        }
        lines.append("source: read-later")
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func yamlString(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func escapeMarkdown(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
    }

    private static func escapeBlockquote(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: "\n> ")
    }
}

extension ISO8601DateFormatter {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let dayOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
