import Foundation

/// Networking front door for feeds: fetches and parses a known feed URL, and
/// resolves a user-pasted URL (site homepage or feed) to a subscribable feed.
enum FeedFetcher {
    struct ResolvedFeed {
        let feedURL: URL
        let parsed: ParsedFeed
    }

    enum FetchError: LocalizedError {
        case badResponse
        case notAFeed
        case noFeedFound

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "The server returned an error."
            case .notAFeed:
                return "That URL isn't an RSS or Atom feed."
            case .noFeedFound:
                return "Couldn't find a feed on that site. Try pasting the feed URL directly."
            }
        }
    }

    /// Fetches and parses a URL already known to be a feed document.
    static func fetch(feedURL: URL) async throws -> ParsedFeed {
        let data = try await get(feedURL)
        do {
            return try FeedParser.parse(data: data)
        } catch {
            throw FetchError.notAFeed
        }
    }

    /// Resolves whatever the user pasted to a feed:
    /// 1. If the URL serves a feed document, use it directly.
    /// 2. Otherwise treat it as HTML and follow declared `<link>` feeds.
    /// 3. Otherwise probe well-known feed paths on the site root.
    static func resolve(url: URL) async throws -> ResolvedFeed {
        let data = try await get(url)

        if FeedDiscovery.isLikelyFeedDocument(data),
           let parsed = try? FeedParser.parse(data: data)
        {
            return ResolvedFeed(feedURL: url, parsed: parsed)
        }

        let html = String(decoding: data, as: UTF8.self)
        var candidates = FeedDiscovery.feedLinks(inHTML: html, baseURL: url).map(\.url)
        if candidates.isEmpty {
            candidates = FeedDiscovery.commonFeedPaths(for: url)
        }

        for candidate in candidates.prefix(6) {
            guard let candidateData = try? await get(candidate),
                  FeedDiscovery.isLikelyFeedDocument(candidateData),
                  let parsed = try? FeedParser.parse(data: candidateData)
            else { continue }
            return ResolvedFeed(feedURL: candidate, parsed: parsed)
        }

        throw FetchError.noFeedFound
    }

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw FetchError.badResponse
        }
        return data
    }
}
