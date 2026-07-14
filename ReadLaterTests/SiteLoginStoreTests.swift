import XCTest
@preconcurrency import WebKit
@testable import ReadLater

/// Exercises `SiteLoginStore`'s host listing and per-site purge against a real
/// but non-persistent `WKWebsiteDataStore`, so the cookie-jar wiring behind the
/// future "sites you're signed into" management screen is verified without
/// touching the shared `.default()` store. The app-hosted test target
/// (`TEST_HOST`) makes WebKit fully available.
@MainActor
final class SiteLoginStoreTests: XCTestCase {

    // MARK: - Pure host helpers

    func testNormalizedHostStripsLeadingDotAndWWW() {
        XCTAssertEqual(SiteLoginStore.normalizedHost(".medium.com"), "medium.com")
        XCTAssertEqual(SiteLoginStore.normalizedHost("www.medium.com"), "medium.com")
        XCTAssertEqual(SiteLoginStore.normalizedHost("Medium.COM"), "medium.com")
        XCTAssertEqual(SiteLoginStore.normalizedHost("sub.medium.com"), "sub.medium.com")
    }

    func testHostMatchesSameHostAndSubdomains() {
        XCTAssertTrue(SiteLoginStore.hostMatches(".medium.com", "medium.com"))
        XCTAssertTrue(SiteLoginStore.hostMatches("sub.medium.com", "medium.com"))
        XCTAssertFalse(SiteLoginStore.hostMatches("notmedium.com", "medium.com"))
        // A parent must not match one of its subdomains.
        XCTAssertFalse(SiteLoginStore.hostMatches("medium.com", "sub.medium.com"))
    }

    // MARK: - Live data-store queries

    func testSignedInHostsListsCookieDomains() async throws {
        let store = SiteLoginStore(dataStore: .nonPersistent())
        try await setCookie(in: store, domain: ".medium.com", name: "sid")
        try await setCookie(in: store, domain: "example.org", name: "token")

        let hosts = await store.signedInHosts()
        XCTAssertEqual(hosts, ["example.org", "medium.com"])
    }

    func testSignOutRemovesOnlyTheTargetHost() async throws {
        let store = SiteLoginStore(dataStore: .nonPersistent())
        try await setCookie(in: store, domain: ".medium.com", name: "sid")
        try await setCookie(in: store, domain: "example.org", name: "token")

        await store.signOut(host: "medium.com")

        let hosts = await store.signedInHosts()
        XCTAssertEqual(hosts, ["example.org"], "only medium.com cookies should be purged")
    }

    // MARK: - Helpers

    /// Seeds a session-style cookie into the store's cookie jar.
    private func setCookie(in store: SiteLoginStore, domain: String, name: String) async throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: "value-\(name)",
            .expires: Date().addingTimeInterval(3600),
        ]))
        let cookieStore = store.dataStore.httpCookieStore
        await withCheckedContinuation { continuation in
            cookieStore.setCookie(cookie) { continuation.resume() }
        }
    }
}
