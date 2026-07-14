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
    /// good enough as a low-level primitive without inspecting cookie contents.
    ///
    /// This is intentionally *unfiltered*: the parser's off-screen `WKWebView`
    /// loads each article's full page, so third-party analytics/CDN domains drop
    /// cookies here too. That makes this list read as cookie soup, not "sites
    /// you signed into." The Settings screen uses ``signedInSites()`` instead,
    /// which filters and groups this raw view into something user-facing.
    func signedInHosts() async -> [String] {
        let cookies = await allCookies()
        var hosts = Set<String>()
        for cookie in cookies {
            hosts.insert(Self.normalizedHost(cookie.domain))
        }
        return hosts.sorted()
    }

    /// Registrable domains the user has a *durable* login for, sorted — the data
    /// source for the "Site Logins" management screen.
    ///
    /// `signedInHosts()` lists every cookie domain in the shared jar, which is
    /// mostly noise: extracting an article loads its full page, so trackers,
    /// analytics, and CDNs all leave cookies. Two filters turn that soup into a
    /// list that reads as "sites":
    ///
    /// 1. **Persistent cookies only** (`!isSessionOnly`). A real login writes a
    ///    cookie with a future expiry so the session survives an app relaunch;
    ///    session-only cookies are in-memory page state that WebKit never
    ///    persists to disk, so they can't represent a login you'd want to manage
    ///    here. This drops a large slice of transient beacon/consent cookies.
    /// 2. **Group by registrable domain** (eTLD+1). Collapses `www.medium.com`,
    ///    `.medium.com`, and subdomains like `accounts.medium.com` into a single
    ///    `medium.com` row, so one site is one entry instead of one-row-per-
    ///    subdomain.
    ///
    /// This is a heuristic, not a guarantee: a tracker that sets a long-lived
    /// first-party-looking cookie can still slip through, and a login that only
    /// uses session cookies won't appear. Both are acceptable — the screen's
    /// explicit per-site Sign Out lets the user prune anything that shouldn't be
    /// there, and a session-only "login" wouldn't survive relaunch anyway.
    func signedInSites() async -> [String] {
        let cookies = await allCookies()
        var domains = Set<String>()
        for cookie in cookies where !cookie.isSessionOnly {
            domains.insert(Self.registrableDomain(cookie.domain))
        }
        return domains.sorted()
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

    /// A small, offline subset of the Public Suffix List: two-label suffixes
    /// under which registrations happen (so `bbc.co.uk` must not collapse to the
    /// bare suffix `co.uk`). We deliberately do **not** vendor the full PSL — it
    /// is a large, frequently-updated data file, and this grouping only drives a
    /// display list, not any security boundary. Anything not listed falls back
    /// to last-two-labels, which is correct for the common gTLD case
    /// (`.com`/`.org`/`.io`/…). Worst case, a site on an unlisted multi-label
    /// ccTLD shows as two rows instead of one — purely cosmetic, and each row's
    /// Sign Out still works.
    private static let twoLevelPublicSuffixes: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk", "me.uk",
        "com.au", "net.au", "org.au", "gov.au", "edu.au",
        "co.jp", "or.jp", "ne.jp",
        "co.nz", "co.za", "co.in", "co.kr",
        "com.br", "com.mx", "com.sg", "com.hk", "com.tr",
    ]

    /// Collapses a cookie domain / host to its registrable domain (eTLD+1) so
    /// subdomains of one site group into a single entry. Uses
    /// ``twoLevelPublicSuffixes`` to keep country-code registrations intact.
    nonisolated static func registrableDomain(_ host: String) -> String {
        let normalized = normalizedHost(host)
        let labels = normalized.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return normalized }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoLevelPublicSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
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
