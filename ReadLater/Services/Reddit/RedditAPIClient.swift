import Foundation

/// The thin, isolated Reddit API surface the rest of the app depends on. Kept
/// behind a protocol on purpose (design doc: "keep the Reddit client thin and
/// isolated behind a protocol so the RSS and JSON backends are swappable and the
/// OAuth surface stays contained"). Everything that talks to Reddit — imports,
/// the reader save-back, the account screen — depends on this abstraction, so
/// the whole live surface can be replaced with a mock in tests (OAuth can't be
/// live-tested without a registered client ID; see the tests).
protocol RedditAPIClientProtocol {
    /// The signed-in account (`identity` scope).
    func account() async throws -> RedditAccount
    /// All subreddits the user subscribes to, following pagination (`mysubreddits`).
    func subscribedSubreddits() async throws -> [RedditSubreddit]
    /// The user's saved *posts* (comments skipped), newest first, capped at
    /// `maxPosts`. `onProgress` reports running count as pages arrive so the
    /// import UI can show live progress. (`history` scope.)
    func savedPosts(username: String, maxPosts: Int, onProgress: (@Sendable (Int) -> Void)?) async throws -> [RedditSavedPost]
    /// Saves a post to the user's Reddit saved list by fullname (`save` scope).
    func save(fullname: String) async throws
    /// Revokes the stored tokens server-side (best-effort sign-out).
    func revokeTokens() async throws
}

/// Supplies a currently-valid access token, refreshing transparently when the
/// stored one is near expiry. Separated from the client so the refresh side
/// effect is injectable/mytestable and the client stays a pure request builder.
protocol RedditTokenProviding {
    /// A non-expired bearer token, refreshing if needed. Throws
    /// `RedditAuthError.notSignedIn` when there is no stored token.
    func validAccessToken() async throws -> String
    /// Forces a refresh (used after a 401). Returns the new token.
    func forceRefresh() async throws -> String
}

/// Concrete client. Rate-limit-respectful: it honors Reddit's `x-ratelimit-*`
/// headers by pausing when the remaining budget hits zero, and backs off on 429.
/// One access token is attached per request via the injected provider; a single
/// transparent refresh-and-retry covers a token that expired mid-session.
final class RedditAPIClient: RedditAPIClientProtocol {
    private let tokenProvider: RedditTokenProviding
    private let session: URLSession
    /// Reddit caps listing pages at 100 items; `after` cursors the next page.
    private let pageSize = 100
    /// Hard ceiling on pagination so a pathological account can't loop forever.
    private let maxPages = 50

    init(tokenProvider: RedditTokenProviding, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Endpoints

    func account() async throws -> RedditAccount {
        let data = try await authorizedGET(path: "/api/v1/me", query: [])
        let decoded = try JSONDecoder().decode(RedditAccountData.self, from: data)
        return RedditAccount(name: decoded.name)
    }

    func subscribedSubreddits() async throws -> [RedditSubreddit] {
        var results: [RedditSubreddit] = []
        var after: String?
        for _ in 0 ..< maxPages {
            let data = try await authorizedGET(
                path: "/subreddits/mine/subscriber",
                query: pageQuery(after: after)
            )
            let listing = try JSONDecoder().decode(RedditListing<RedditSubredditData>.self, from: data)
            results.append(contentsOf: listing.children.compactMap { $0.data }.compactMap(RedditParsing.subreddit))
            guard let next = listing.after, !next.isEmpty else { break }
            after = next
        }
        // De-dup by fullname (defensive) and sort by name for a stable picker.
        var seen = Set<String>()
        return results
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func savedPosts(
        username: String,
        maxPosts: Int,
        onProgress: (@Sendable (Int) -> Void)?
    ) async throws -> [RedditSavedPost] {
        var results: [RedditSavedPost] = []
        var after: String?
        let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        for _ in 0 ..< maxPages {
            let data = try await authorizedGET(
                path: "/user/\(encodedUser)/saved",
                query: pageQuery(after: after)
            )
            let listing = try JSONDecoder().decode(RedditListing<RedditLinkData>.self, from: data)
            // Only link posts (t3) decode into RedditLinkData; saved comments
            // (t1) fail to decode their required fields, so decode per-child and
            // skip failures rather than failing the whole page.
            for child in listing.children where child.kind == "t3" {
                guard let linkData = child.data else { continue }
                results.append(RedditParsing.savedPost(from: linkData))
                if results.count >= maxPosts { break }
            }
            onProgress?(results.count)
            if results.count >= maxPosts { break }
            guard let next = listing.after, !next.isEmpty else { break }
            after = next
        }
        return Array(results.prefix(maxPosts))
    }

    func save(fullname: String) async throws {
        _ = try await authorizedPOST(path: "/api/save", form: ["id": fullname])
    }

    func revokeTokens() async throws {
        // Revocation hits www.reddit.com with Basic auth (not the bearer host).
        guard let tokens = RedditTokenStore.load() else { return }
        if let refresh = tokens.refreshToken {
            try? await revoke(token: refresh, isRefreshToken: true)
        }
        try? await revoke(token: tokens.accessToken, isRefreshToken: false)
    }

    // MARK: - Request plumbing

    private func pageQuery(after: String?) -> [URLQueryItem] {
        var q = [URLQueryItem(name: "limit", value: String(pageSize)), URLQueryItem(name: "raw_json", value: "1")]
        if let after { q.append(URLQueryItem(name: "after", value: after)) }
        return q
    }

    private func authorizedGET(path: String, query: [URLQueryItem]) async throws -> Data {
        var comps = URLComponents(url: RedditAuthConfig.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { comps?.queryItems = query }
        guard let url = comps?.url else { throw RedditAuthError.network("Bad request URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func authorizedPOST(path: String, form: [String: String]) async throws -> Data {
        let url = RedditAuthConfig.apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)
        return try await send(request)
    }

    /// Attaches the bearer token + UA, sends, honors rate-limit headers, and
    /// transparently refreshes once on a 401.
    private func send(_ request: URLRequest, isRetry: Bool = false) async throws -> Data {
        var request = request
        let token = try await tokenProvider.validAccessToken()
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(RedditAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RedditAuthError.network("No HTTP response from Reddit.")
        }

        switch http.statusCode {
        case 200 ... 299:
            await respectRateLimit(headers: http)
            return data
        case 401 where !isRetry:
            // Access token rejected — refresh once and retry.
            _ = try await tokenProvider.forceRefresh()
            return try await send(request, isRetry: true)
        case 429:
            // Throttled: pause for the advertised reset, then retry once.
            let retryAfter = Double(http.value(forHTTPHeaderField: "retry-after") ?? "") ?? 5
            if !isRetry {
                try await Task.sleep(for: .seconds(min(retryAfter, 30)))
                return try await send(request, isRetry: true)
            }
            throw RedditAuthError.network("Reddit is rate-limiting requests. Try again shortly.")
        default:
            throw RedditAuthError.network("Reddit returned HTTP \(http.statusCode).")
        }
    }

    /// Proactive politeness: when Reddit reports zero remaining requests in the
    /// current window, wait out the reset before returning so the next call
    /// doesn't immediately 429. Header values are floats/seconds.
    private func respectRateLimit(headers http: HTTPURLResponse) async {
        guard let remainingStr = http.value(forHTTPHeaderField: "x-ratelimit-remaining"),
              let remaining = Double(remainingStr), remaining < 1
        else { return }
        let reset = Double(http.value(forHTTPHeaderField: "x-ratelimit-reset") ?? "") ?? 1
        try? await Task.sleep(for: .seconds(min(max(reset, 1), 60)))
    }

    private func revoke(token: String, isRefreshToken: Bool) async throws {
        var request = URLRequest(url: RedditAuthConfig.revokeURL)
        request.httpMethod = "POST"
        request.setValue(RedditOAuth.basicAuthHeader(clientID: RedditAuthConfig.clientID), forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(RedditAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(RedditOAuth.revokeBody(token: token, isRefreshToken: isRefreshToken).utf8)
        _ = try? await session.data(for: request)
    }

    private func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}

/// Production token provider: reads the stored bundle, refreshes via the token
/// endpoint when near expiry, and persists the rotated tokens back to Keychain.
final class RedditTokenProvider: RedditTokenProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validAccessToken() async throws -> String {
        guard let tokens = RedditTokenStore.load() else { throw RedditAuthError.notSignedIn }
        if tokens.isExpired() { return try await forceRefresh() }
        return tokens.accessToken
    }

    func forceRefresh() async throws -> String {
        guard let tokens = RedditTokenStore.load(), let refresh = tokens.refreshToken else {
            throw RedditAuthError.notSignedIn
        }
        var request = URLRequest(url: RedditAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue(RedditOAuth.basicAuthHeader(clientID: RedditAuthConfig.clientID), forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(RedditAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(RedditOAuth.refreshBody(refreshToken: refresh).utf8)

        let (data, _) = try await session.data(for: request)
        let parsed = try RedditOAuth.parseTokenResponse(data)
        var updated = tokens
        updated.accessToken = parsed.accessToken
        updated.expiresAt = Date().addingTimeInterval(TimeInterval(parsed.expiresIn))
        updated.scope = parsed.scope
        // Reddit omits refresh_token on refresh; keep the existing one.
        if let newRefresh = parsed.refreshToken { updated.refreshToken = newRefresh }
        RedditTokenStore.save(updated)
        return updated.accessToken
    }
}
