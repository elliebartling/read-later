import Foundation

/// Finds the feed behind a URL the user pasted — which is usually a site
/// homepage, not the feed document itself.
enum FeedDiscovery {
    struct DiscoveredFeed {
        let url: URL
        let title: String?
    }

    private static let feedMIMETypes: Set<String> = [
        "application/rss+xml",
        "application/atom+xml",
        "application/rdf+xml",
    ]

    /// Cheap sniff: does this response body look like a feed document rather
    /// than an HTML page? Checks marker order so an HTML page that merely
    /// mentions "<rss" deep in its body doesn't pass.
    static func isLikelyFeedDocument(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        let feedIndex = ["<rss", "<feed", "<rdf:rdf"]
            .compactMap { head.range(of: $0)?.lowerBound }
            .min()
        guard let feedIndex else { return false }
        if let htmlIndex = head.range(of: "<html")?.lowerBound {
            return feedIndex < htmlIndex
        }
        return true
    }

    /// Extracts `<link rel="alternate" type="application/rss+xml" …>` feed
    /// declarations from an HTML page, resolving relative hrefs against the
    /// page URL. Order follows document order, so a site's preferred feed
    /// (listed first) comes out first.
    static func feedLinks(inHTML html: String, baseURL: URL?) -> [DiscoveredFeed] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: "<link\\b[^>]*>",
            options: .caseInsensitive
        ) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        var found: [DiscoveredFeed] = []
        var seen: Set<URL> = []

        for match in tagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let attrs = attributes(inTag: String(html[tagRange]))

            let rels = (attrs["rel"] ?? "").lowercased().split(separator: " ")
            guard rels.contains("alternate") else { continue }
            guard let type = attrs["type"]?.lowercased(),
                  feedMIMETypes.contains(type) else { continue }
            guard let href = attrs["href"], !href.isEmpty,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }

            if seen.insert(url).inserted {
                found.append(DiscoveredFeed(url: url, title: attrs["title"]))
            }
        }
        return found
    }

    /// Well-known feed locations to probe when a page declares no feed links.
    /// Covers WordPress, Ghost, Hugo, Jekyll, and friends.
    static func commonFeedPaths(for url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }
        components.query = nil
        components.fragment = nil
        components.path = ""
        guard let root = components.url else { return [] }
        return ["feed", "rss", "rss.xml", "atom.xml", "feed.xml", "index.xml"]
            .compactMap { URL(string: $0, relativeTo: root)?.absoluteURL }
    }

    /// Pulls attribute key/value pairs out of a single HTML tag. Handles
    /// double-quoted, single-quoted, and bare values.
    private static func attributes(inTag tag: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: "([a-zA-Z][a-zA-Z0-9_:-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        ) else { return [:] }

        var attrs: [String: String] = [:]
        let range = NSRange(tag.startIndex..., in: tag)
        for match in attrRegex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let key = tag[keyRange].lowercased()
            for group in 2...4 {
                if let valueRange = Range(match.range(at: group), in: tag) {
                    attrs[key] = String(tag[valueRange])
                    break
                }
            }
        }
        return attrs
    }
}
