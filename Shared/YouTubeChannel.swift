import Foundation

/// Resolves a YouTube channel reference (a `/channel/UC…` URL, a `@handle`, or a
/// legacy `/c/…` / `/user/…` vanity URL) to its anonymous, quota-less Atom feed:
/// `https://www.youtube.com/feeds/videos.xml?channel_id=UC…`.
///
/// The classification and channel-id parsing are pure and unit-testable; the
/// only impure piece is `resolveFeedURL`, which fetches a channel page when the
/// reference is a handle/vanity URL (there is no id in those, so the page's
/// metadata is the only place the `UC…` id lives). Handle resolution is honest
/// scraping and *will* be fragile — YouTube can reshape that markup any time —
/// so failure surfaces a clear "paste the full channel URL" error.
enum YouTubeChannel {

    /// A user-pasted channel reference, classified.
    enum Reference: Equatable {
        /// A direct `channel_id` — the feed URL builds with no network.
        case channelID(String)
        /// A handle/vanity page whose id must be scraped from its HTML.
        case needsResolution(URL)
    }

    enum ResolveError: LocalizedError {
        case handleUnresolved

        var errorDescription: String? {
            switch self {
            case .handleUnresolved:
                return "Couldn't find that YouTube channel. Paste the full channel URL (youtube.com/channel/UC…)."
            }
        }
    }

    /// Builds the Atom feed URL for a known channel id.
    static func feedURL(channelID id: String) -> URL? {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)")
    }

    /// Classifies raw input as a YouTube channel reference, or nil when it is not
    /// a channel reference at all (a watch URL, a non-YouTube URL, a bare
    /// domain, …) — the caller then falls through to normal feed resolution.
    /// Pure and unit-testable.
    static func reference(from raw: String) -> Reference? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare `@handle` (no scheme/host).
        if trimmed.hasPrefix("@"), !trimmed.contains("/"), isValidHandleBody(String(trimmed.dropFirst())) {
            if let url = URL(string: "https://www.youtube.com/\(trimmed)") {
                return .needsResolution(url)
            }
            return nil
        }

        // Anything else must be a YouTube URL (with or without scheme).
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              YouTubeURL.isYouTubeHost(url.host),
              url.host?.lowercased() != "youtu.be"
        else { return nil }

        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first else { return nil }

        // /channel/UC… → direct id.
        if first.lowercased() == "channel", segments.count >= 2 {
            let id = segments[1]
            return isValidChannelID(id) ? .channelID(id) : nil
        }
        // /@handle → resolve.
        if first.hasPrefix("@"), isValidHandleBody(String(first.dropFirst())) {
            return .needsResolution(url)
        }
        // Legacy /c/<name> and /user/<name> → resolve.
        if ["c", "user"].contains(first.lowercased()), segments.count >= 2 {
            return .needsResolution(url)
        }
        return nil
    }

    /// Extracts a `UC…` channel id from a fetched channel page's HTML. Tries the
    /// stable, redundant places YouTube stamps the id: the `channelId` /
    /// `externalId` JSON keys, the `<meta itemprop="channelId">` tag, and the
    /// canonical `/channel/UC…` link. Pure and unit-testable.
    static func channelID(fromHTML html: String) -> String? {
        let patterns = [
            "\"channelId\":\"(UC[0-9A-Za-z_-]{22})\"",
            "\"externalId\":\"(UC[0-9A-Za-z_-]{22})\"",
            "itemprop=\"channelId\"[^>]*content=\"(UC[0-9A-Za-z_-]{22})\"",
            "/channel/(UC[0-9A-Za-z_-]{22})",
        ]
        for pattern in patterns {
            if let id = firstCapture(pattern, in: html), isValidChannelID(id) {
                return id
            }
        }
        return nil
    }

    /// Resolves any channel reference in `raw` to its feed URL, fetching the
    /// channel page when a handle/vanity URL needs scraping. Returns nil when
    /// `raw` is not a YouTube channel reference (caller uses normal resolution);
    /// throws `ResolveError.handleUnresolved` when a handle page can't be scraped.
    static func resolveFeedURL(from raw: String) async throws -> URL? {
        guard let reference = reference(from: raw) else { return nil }
        switch reference {
        case .channelID(let id):
            return feedURL(channelID: id)
        case .needsResolution(let url):
            let html = try await fetchChannelHTML(url)
            guard let id = channelID(fromHTML: html), let feed = feedURL(channelID: id) else {
                throw ResolveError.handleUnresolved
            }
            return feed
        }
    }

    // MARK: - Private

    private static func fetchChannelHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // A desktop UA gets the full channel page (mobile redirects lose the
        // metadata surface we scrape the id from).
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw ResolveError.handleUnresolved
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Channel ids are `UC` followed by 22 URL-safe base64 characters.
    static func isValidChannelID(_ id: String) -> Bool {
        guard id.count == 24, id.hasPrefix("UC") else { return false }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Handle bodies (after the `@`): letters, digits, dot, dash, underscore;
    /// 3–30 chars per YouTube's rules.
    private static func isValidHandleBody(_ body: String) -> Bool {
        guard (3 ... 30).contains(body.count) else { return false }
        return body.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }
}
