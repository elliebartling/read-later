import Foundation

/// The persisted Reddit OAuth token bundle. Access + refresh tokens are secrets
/// and live only in Keychain (never UserDefaults / SwiftData), reusing the
/// existing `KeychainStore` primitive — the same pattern as the OpenAI key. The
/// signed-in username is stored alongside so it purges together on sign-out.
struct RedditStoredTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    /// Absolute expiry of `accessToken`. Refreshed proactively before it lapses.
    var expiresAt: Date
    var scope: String
    /// The signed-in account name (from the `identity` scope), for UI display.
    /// Not a secret, but kept in the same blob so one delete clears everything.
    var username: String?

    /// True when the access token is within `leeway` of expiring (or already
    /// expired) and should be refreshed before the next API call.
    func isExpired(now: Date = .now, leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Keychain-backed persistence for the Reddit token bundle. A thin JSON wrapper
/// over `KeychainStore` (one account, one encoded blob) so the whole bundle is
/// written and cleared atomically.
enum RedditTokenStore {
    private static let account = "reddit.oauth.tokens"

    static func load() -> RedditStoredTokens? {
        guard let json = KeychainStore.get(account: account),
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder.iso8601.decode(RedditStoredTokens.self, from: data)
    }

    @discardableResult
    static func save(_ tokens: RedditStoredTokens) -> Bool {
        guard let data = try? JSONEncoder.iso8601.encode(tokens),
              let json = String(data: data, encoding: .utf8)
        else { return false }
        return KeychainStore.set(json, account: account)
    }

    static func clear() {
        KeychainStore.delete(account: account)
    }

    static var hasTokens: Bool { load() != nil }
}
