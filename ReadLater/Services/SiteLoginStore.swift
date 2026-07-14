import Foundation
@preconcurrency import WebKit

/// Central owner of the persistent website-data store shared by the article
/// parser's off-screen `WKWebView` (`ArticleParser`) and the in-app site-login
/// sheet (`SiteLoginView`). Both are configured with `dataStore`, so cookies a
/// user establishes by signing in on a site's own pages are visible to the
/// parser on the very next extraction — that is the whole mechanism behind
/// in-app site login. We never read or write credentials; the site sets its own
/// session cookies, we just persist and reuse them.
///
/// `WKWebsiteDataStore.default()` is a process-wide singleton persistent store,
/// so any `WKWebView` configured with it shares one cookie jar. `ArticleParser`
/// previously relied on this implicitly (a bare `WKWebViewConfiguration`
/// defaults to `.default()`); routing both through this type makes the shared
/// contract explicit and gives a single place to evolve it.
///
/// - Note: The read/purge queries below (`signedInHosts()`, `signOut(host:)`)
///   exist so a future Settings screen — "sites you're signed into" with a
///   per-site "Sign out" — is a thin call away. That management UI is
///   deliberately **out of scope for v1** (see the site-login PR); this type is
///   the seam it will build on. The queries are unit-tested against an injected
///   non-persistent store so the host-matching logic is verified now.
@MainActor
final class SiteLoginStore {
    static let shared = SiteLoginStore()

    /// The persistent data store shared across the app's `WKWebView`s. Defaults
    /// to the process-wide `.default()` singleton; tests inject a
    /// `.nonPersistent()` store to exercise the host queries in isolation.
    let dataStore: WKWebsiteDataStore

    init(dataStore: WKWebsiteDataStore = .default()) {
        self.dataStore = dataStore
    }

    /// Hosts that currently have at least one stored cookie, normalized and
    /// sorted. Cookie presence is a deliberately coarse proxy for "signed in" —
    /// good enough to populate a management list without inspecting cookie
    /// contents. Backs a future "sites you're signed into" screen.
    func signedInHosts() async -> [String] {
        let cookies = await allCookies()
        var hosts = Set<String>()
        for cookie in cookies {
            hosts.insert(Self.normalizedHost(cookie.domain))
        }
        return hosts.sorted()
    }

    /// Removes all website data (cookies, cache, local storage) for `host` and
    /// its subdomains — the "sign out of this site" action. Matching is
    /// registrable-domain aware so a session cookie scoped to `.medium.com`
    /// (or `sub.medium.com`) is cleared when signing out of `medium.com`.
    func signOut(host: String) async {
        let target = Self.normalizedHost(host)

        // Cookies match by domain, which may be dot-prefixed for subdomains.
        let cookieStore = dataStore.httpCookieStore
        for cookie in await allCookies() where Self.hostMatches(cookie.domain, target) {
            await deleteCookie(cookie, from: cookieStore)
        }

        // Non-cookie records (cache, local/session storage) are keyed by a
        // display name that is the registrable domain.
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let matching = records.filter { Self.hostMatches($0.displayName, target) }
        if !matching.isEmpty {
            await dataStore.removeData(ofTypes: types, for: matching)
        }
    }

    // MARK: - Pure host helpers (unit-tested)

    /// Strips a leading cookie dot and a `www.` prefix, lowercased, so cookie
    /// domains and data-record display names collapse to a comparable host.
    nonisolated static func normalizedHost(_ domain: String) -> String {
        var d = domain
        if d.hasPrefix(".") { d.removeFirst() }
        if d.hasPrefix("www.") { d.removeFirst(4) }
        return d.lowercased()
    }

    /// True when `candidate` (a cookie domain or record display name) belongs to
    /// `target` — either the same host or a subdomain of it.
    nonisolated static func hostMatches(_ candidate: String, _ target: String) -> Bool {
        let c = normalizedHost(candidate)
        let t = normalizedHost(target)
        return c == t || c.hasSuffix("." + t)
    }

    // MARK: - WebKit continuation bridges

    private func allCookies() async -> [HTTPCookie] {
        let store = dataStore.httpCookieStore
        return await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private func deleteCookie(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }
}
