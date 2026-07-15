import Foundation

/// Reddit-specific feed logic, kept pure and dependency-free so every branch is
/// unit-testable without a network or a store. Reddit rides on the generic
/// RSS/Atom pipeline; these helpers layer the few Reddit-only behaviours on top
/// (link-vs-self classification, `r/name` shorthand, host detection).
enum RedditFeed {

    /// Canonical host used when normalizing shorthand.
    static let canonicalHost = "www.reddit.com"

    /// True for reddit.com and its subdomains (www, old, m, np, i, …). Matches
    /// on the registrable domain so `old.reddit.com` and `www.reddit.com` are
    /// both treated as Reddit.
    static func isRedditHost(_ host: String?) -> Bool {
        guard var host = host?.lowercased(), !host.isEmpty else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return host == "reddit.com" || host.hasSuffix(".reddit.com")
    }

    /// True when `url` points at a reddit.com-family host.
    static func isRedditURL(_ url: URL?) -> Bool {
        isRedditHost(url?.host)
    }

    // MARK: - `r/name` shorthand

    /// Normalizes a subreddit shorthand to its Atom feed URL:
    ///   `r/ios`, `/r/ios`, `reddit.com/r/ios`, `www.reddit.com/r/ios`
    ///   (optionally with a trailing slash) → `https://www.reddit.com/r/ios/.rss`.
    ///
    /// Returns nil for anything that isn't a bare subreddit reference — sort
    /// variants (`r/ios/top`), explicit `.rss` URLs, query strings, and full
    /// non-shorthand URLs are left for the normal resolver to handle literally.
    static func normalizeSubredditShorthand(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        // Strip an optional scheme.
        if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
        }
        // Strip an optional reddit host prefix.
        for host in ["www.reddit.com", "reddit.com", "old.reddit.com", "m.reddit.com"] {
            if s.hasPrefix(host) {
                s = String(s.dropFirst(host.count))
                break
            }
        }
        // Drop a single leading slash and a single trailing slash.
        if s.hasPrefix("/") { s.removeFirst() }
        if s.hasSuffix("/") { s.removeLast() }

        // Must be exactly `r/<name>` with no further path/query segments.
        guard s.hasPrefix("r/") else { return nil }
        let name = String(s.dropFirst(2))
        guard !name.isEmpty, isValidSubredditName(name) else { return nil }

        return URL(string: "https://\(canonicalHost)/r/\(name)/.rss")
    }

    /// Reddit subreddit names: letters, digits, and underscores.
    private static func isValidSubredditName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - Narwhal deep link

    /// URL scheme Narwhal 2 registers; must be in `LSApplicationQueriesSchemes`
    /// (see project.yml) for `canOpenURL` to answer truthfully.
    static let narwhalScheme = "narwhal"

    /// Builds Narwhal 2's deep link for an arbitrary reddit.com URL:
    /// `narwhal://open-url/<percent-encoded URL>`. Returns nil if the URL can't
    /// be percent-encoded. (Verified against Narwhal 2's community URI-rewrite
    /// userscript, which does exactly `narwhal://open-url/ + encodeURIComponent`.)
    static func narwhalURL(forPermalink permalink: URL) -> URL? {
        // Match JS encodeURIComponent: encode everything except unreserved marks.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        guard let encoded = permalink.absoluteString
            .addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "\(narwhalScheme)://open-url/\(encoded)")
    }

    // MARK: - Link vs self classification

    /// Extracts a link post's external destination from the entry's content
    /// HTML. Reddit appends `[link]` and `[comments]` anchors to every entry's
    /// content; when the `[link]` target differs from the `[comments]` target
    /// the post is a link post and the `[link]` target is its external URL.
    /// Returns nil for self posts (the two targets match, or no `[link]` is
    /// present), which is the caller's signal to render the post body instead.
    static func externalURL(fromContentHTML html: String?) -> URL? {
        guard let html, !html.isEmpty else { return nil }
        guard let linkHref = anchorHref(labeled: "link", in: html) else { return nil }
        let commentsHref = anchorHref(labeled: "comments", in: html)

        // Self post: [link] and [comments] both point at the permalink.
        if let commentsHref, linkHref == commentsHref { return nil }
        return URL(string: linkHref)
    }

    /// Finds the `href` of the anchor whose visible text is exactly `[<label>]`
    /// (Reddit's `[link]` / `[comments]` footer anchors), entity-decoded.
    private static func anchorHref(labeled label: String, in html: String) -> String? {
        // <a href="URL" …>[label]</a>  — href may carry other attributes.
        let pattern = "<a\\s+[^>]*href=\"([^\"]+)\"[^>]*>\\s*\\[\(label)\\]\\s*</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let hrefRange = Range(match.range(at: 1), in: html)
        else { return nil }
        let raw = String(html[hrefRange])
        let decoded = FeedParser.decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }
}

/// Pure serialization policy for feed refresh. Reddit throttles anonymous
/// fetches hard (~1 req/min/IP documented), so reddit.com-family feeds must
/// refresh sequentially with spacing while everything else stays concurrent.
enum RedditPolicy {

    /// Polite gap between consecutive Reddit fetches. A compromise: Reddit's
    /// documented anonymous ceiling is ~1/min, but that makes a multi-subreddit
    /// refresh feel broken, so we serialize (never parallel) and space lightly.
    static let refreshSpacing: Duration = .seconds(2)

    /// Descriptive User-Agent for Reddit requests. Reddit 429s generic agents
    /// (and the default URLSession token) far more aggressively than a unique,
    /// app-identifying one.
    static let userAgent = "ios:com.ellenbartling.readlater:v0.1 (Read Later RSS)"

    /// Splits feed URLs into those that may fetch concurrently and those that
    /// must fetch sequentially (Reddit-family hosts). Pure and order-preserving
    /// so the refresh scheduler's decision is unit-testable.
    static func partition(_ urls: [URL]) -> (concurrent: [URL], sequential: [URL]) {
        var concurrent: [URL] = []
        var sequential: [URL] = []
        for url in urls {
            if RedditFeed.isRedditURL(url) {
                sequential.append(url)
            } else {
                concurrent.append(url)
            }
        }
        return (concurrent, sequential)
    }
}
