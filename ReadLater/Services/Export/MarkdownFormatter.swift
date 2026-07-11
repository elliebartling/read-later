import Foundation

/// Renders an Article + its highlights as Obsidian-friendly markdown.
///
/// Export uses a MANAGED SECTION: the app only ever rewrites the region
/// between `%% readlater:start %%` and `%% readlater:end %%` (Obsidian
/// comment syntax — invisible in preview). Anything the user writes outside
/// the markers survives every export. Frontmatter is written once, on file
/// creation, and never touched again.
///
/// Rendering is deterministic — same article + highlight set produces the same
/// bytes — so repeated exports don't churn file watchers.
enum MarkdownFormatter {

    static let managedSectionStart = "%% readlater:start %%"
    static let managedSectionEnd = "%% readlater:end %%"

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

    /// Full contents for a NEW file: frontmatter + managed section.
    static func render(_ input: RenderInput) -> String {
        frontmatter(for: input.article) + "\n\n" + managedSection(input) + "\n"
    }

    /// Merges a fresh managed section into an EXISTING file, replacing only
    /// the marker-delimited region. If the markers are missing (user deleted
    /// them, or the file predates this format), the section is appended to the
    /// end — never overwriting anything.
    static func merge(existing: String, input: RenderInput) -> String {
        let section = managedSection(input)
        guard let startRange = existing.range(of: managedSectionStart),
              let endRange = existing.range(of: managedSectionEnd),
              startRange.lowerBound < endRange.upperBound
        else {
            let trimmed = existing.hasSuffix("\n") ? existing : existing + "\n"
            return trimmed + "\n" + section + "\n"
        }
        return existing.replacingCharacters(in: startRange.lowerBound..<endRange.upperBound, with: section)
    }

    /// The marker-delimited block: title, byline, link, highlights.
    static func managedSection(_ input: RenderInput) -> String {
        var out = managedSectionStart + "\n"
        out.append("# \(escapeMarkdown(input.article.title))\n\n")
        if let author = input.article.author {
            out.append("*by \(author)*\n\n")
        }
        if let url = input.article.url {
            out.append("[Original link](\(url.absoluteString))\n\n")
        }
        if !input.highlights.isEmpty {
            out.append("## Highlights\n\n")
            let sorted = input.highlights.sorted { $0.startOffset < $1.startOffset }
            for h in sorted {
                // Dataview inline-field form. NOT [[color::x]] — double
                // brackets create a wikilink node in the user's graph.
                let colorField = "(color:: \(h.color.rawValue))"
                out.append("> \(escapeBlockquote(h.quotedText)) \(colorField)\n")
                if let note = h.note, !note.isEmpty {
                    out.append(">\n> **Note:** \(escapeBlockquote(note))\n")
                }
                out.append("\n")
            }
        }
        out.append(managedSectionEnd)
        return out
    }

    private static func frontmatter(for article: Article) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \(yamlString(article.title))")
        if let url = article.url {
            lines.append("url: \(yamlString(url.absoluteString))")
        }
        if let a = article.author { lines.append("author: \(yamlString(a))") }
        if let s = article.siteName { lines.append("site: \(yamlString(s))") }
        lines.append("savedAt: \(ISO8601DateFormatter.iso8601.string(from: article.savedAt))")
        let tags = article.allTags
        if !tags.isEmpty {
            let list = tags.map { "\"\($0.name)\"" }.joined(separator: ", ")
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
