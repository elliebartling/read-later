import SwiftData
import XCTest
@testable import ReadLater

/// Reddit wave 2 — data-shaping and import logic: fullname derivation from a
/// permalink, saved-post normalization (self vs link), subreddit mapping,
/// paginated listing assembly (exercised through the real client over a stubbed
/// URLProtocol), the import dedupe planner, and subreddit → Feed subscription.
final class RedditImportTests: XCTestCase {

    // MARK: - Fullname derivation (reader save-back)

    func testPostFullnameFromPermalink() {
        let url = URL(string: "https://www.reddit.com/r/swift/comments/abc123/some_slug/")!
        XCTAssertEqual(RedditParsing.postFullname(fromPermalink: url), "t3_abc123")
    }

    func testPostFullnameFromPermalinkNoSlug() {
        let url = URL(string: "https://www.reddit.com/r/swift/comments/xyz789")!
        XCTAssertEqual(RedditParsing.postFullname(fromPermalink: url), "t3_xyz789")
    }

    func testPostFullnameNilForNonCommentsURL() {
        XCTAssertNil(RedditParsing.postFullname(fromPermalink: URL(string: "https://www.reddit.com/r/swift/")!))
        XCTAssertNil(RedditParsing.postFullname(fromPermalink: URL(string: "https://example.com/article")!))
    }

    // MARK: - Saved-post normalization

    func testSavedPostSelfPostRoutesToPermalinkAndBody() {
        let data = RedditLinkData(
            name: "t3_self1",
            title: "A text post",
            url: "https://www.reddit.com/r/swift/comments/self1/a_text_post/",
            permalink: "/r/swift/comments/self1/a_text_post/",
            isSelf: true,
            selftextHTML: "&lt;p&gt;Body &amp; text&lt;/p&gt;",
            subreddit: "swift"
        )
        let post = RedditParsing.savedPost(from: data)
        XCTAssertTrue(post.isSelf)
        // Self post: url is the permalink; body HTML decoded one level.
        XCTAssertEqual(post.url?.absoluteString, "https://www.reddit.com/r/swift/comments/self1/a_text_post/")
        XCTAssertEqual(post.permalink?.absoluteString, "https://www.reddit.com/r/swift/comments/self1/a_text_post/")
        XCTAssertEqual(post.selfTextHTML, "<p>Body & text</p>")
    }

    func testSavedPostLinkPostRoutesToExternalURL() {
        let data = RedditLinkData(
            name: "t3_link1",
            title: "A link post",
            url: "https://blog.example.com/great",
            permalink: "/r/swift/comments/link1/a_link_post/",
            isSelf: false,
            selftextHTML: nil,
            subreddit: "swift"
        )
        let post = RedditParsing.savedPost(from: data)
        XCTAssertFalse(post.isSelf)
        XCTAssertEqual(post.url?.absoluteString, "https://blog.example.com/great")
        // Permalink expands to absolute reddit.com for discussionURL.
        XCTAssertEqual(post.permalink?.absoluteString, "https://www.reddit.com/r/swift/comments/link1/a_link_post/")
        XCTAssertNil(post.selfTextHTML, "link posts carry no captured body")
    }

    // MARK: - Subreddit mapping

    func testSubredditMappingAndFeedURL() {
        let data = RedditSubredditData(name: "t5_2fgh", displayName: "swift", title: "Swift", subscribers: 120_000)
        let sub = try? XCTUnwrap(RedditParsing.subreddit(from: data))
        XCTAssertEqual(sub?.id, "t5_2fgh")
        XCTAssertEqual(sub?.name, "swift")
        XCTAssertEqual(sub?.feedURL?.absoluteString, "https://www.reddit.com/r/swift/.rss")
    }

    func testSubredditMappingDropsEntriesWithoutFullname() {
        let data = RedditSubredditData(name: nil, displayName: "swift", title: nil, subscribers: nil)
        XCTAssertNil(RedditParsing.subreddit(from: data))
    }

    // MARK: - Pagination assembly (real client over a stubbed transport)

    @MainActor
    func testSubscribedSubredditsFollowsPagination() async throws {
        // Page 1 → after cursor; page 2 → after null (terminates). The client
        // must concatenate both pages and sort by name.
        StubURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            let body: String
            if query.contains("after=") {
                body = Self.listing(children: [Self.subredditChild(name: "t5_2", display: "ios")], after: nil)
            } else {
                body = Self.listing(children: [Self.subredditChild(name: "t5_1", display: "swift")], after: "t5_2")
            }
            return (200, [:], Data(body.utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let client = RedditAPIClient(tokenProvider: MockTokenProvider(), session: Self.stubbedSession())
        let subs = try await client.subscribedSubreddits()
        XCTAssertEqual(subs.map(\.name), ["ios", "swift"], "both pages combined and sorted")
    }

    @MainActor
    func testSavedPostsSkipsCommentsAndHonorsCap() async throws {
        // A page mixing a link post (t3), a comment (t1), and a self post (t3).
        // Comments are skipped; the cap bounds the result.
        StubURLProtocol.handler = { _ in
            let children = [
                Self.linkChild(name: "t3_a", title: "Link A", url: "https://a.example/x", isSelf: false),
                Self.commentChild(),
                Self.linkChild(name: "t3_b", title: "Self B", url: nil, isSelf: true),
            ]
            return (200, [:], Data(Self.listing(children: children, after: nil).utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let client = RedditAPIClient(tokenProvider: MockTokenProvider(), session: Self.stubbedSession())
        let posts = try await client.savedPosts(username: "me", maxPosts: 5, onProgress: nil)
        XCTAssertEqual(posts.map(\.id), ["t3_a", "t3_b"], "t1 comment skipped, t3 posts kept")
    }

    // MARK: - Import dedupe planner

    func testImportPlanDedupesAgainstExistingAndWithinBatch() {
        let posts = [
            RedditSavedPost(id: "t3_1", title: "One", url: URL(string: "https://a.example/1"),
                            permalink: URL(string: "https://www.reddit.com/r/x/comments/1/one/"),
                            isSelf: false, selfTextHTML: nil, subreddit: "x"),
            // Duplicate of an already-saved article (normalized: trailing slash).
            RedditSavedPost(id: "t3_2", title: "Two", url: URL(string: "https://b.example/2/"),
                            permalink: nil, isSelf: false, selfTextHTML: nil, subreddit: "x"),
            // Duplicate within the batch (same URL as t3_1, different case/host).
            RedditSavedPost(id: "t3_3", title: "Three", url: URL(string: "https://A.example/1"),
                            permalink: nil, isSelf: false, selfTextHTML: nil, subreddit: "x"),
            // No URL ⇒ skipped.
            RedditSavedPost(id: "t3_4", title: "Four", url: nil,
                            permalink: nil, isSelf: false, selfTextHTML: nil, subreddit: "x"),
        ]
        let existing: Set<String> = [RedditImportPlan.normalize(URL(string: "https://b.example/2")!)]
        let plan = RedditImportPlan.plan(savedPosts: posts, existingURLs: existing)

        XCTAssertEqual(plan.saves.count, 1, "only the first unique, non-existing post survives")
        XCTAssertEqual(plan.saves.first?.url.absoluteString, "https://a.example/1")
        XCTAssertEqual(plan.skipped, 3, "existing dup + in-batch dup + no-URL")
    }

    func testImportPlanRoutesSelfVsLink() {
        let selfPost = RedditSavedPost(id: "t3_s", title: "Self", url: URL(string: "https://www.reddit.com/r/x/comments/s/self/"),
                                       permalink: URL(string: "https://www.reddit.com/r/x/comments/s/self/"),
                                       isSelf: true, selfTextHTML: "<p>body</p>", subreddit: "x")
        let linkPost = RedditSavedPost(id: "t3_l", title: "Link", url: URL(string: "https://ext.example/a"),
                                       permalink: URL(string: "https://www.reddit.com/r/x/comments/l/link/"),
                                       isSelf: false, selfTextHTML: nil, subreddit: "x")
        let plan = RedditImportPlan.plan(savedPosts: [selfPost, linkPost], existingURLs: [])
        XCTAssertEqual(plan.saves.count, 2)
        let bySelf = plan.saves.first { $0.capturedHTML != nil }
        XCTAssertEqual(bySelf?.capturedHTML, "<p>body</p>", "self post carries captured body")
        XCTAssertEqual(bySelf?.discussionURL?.absoluteString, "https://www.reddit.com/r/x/comments/s/self/")
        let byLink = plan.saves.first { $0.capturedHTML == nil }
        XCTAssertEqual(byLink?.url.absoluteString, "https://ext.example/a")
        XCTAssertEqual(byLink?.discussionURL?.absoluteString, "https://www.reddit.com/r/x/comments/l/link/")
    }

    // MARK: - Subreddit subscription (wave-1 machinery)

    @MainActor
    func testSubscribeCreatesFeedsAndSkipsExisting() throws {
        let schema = Schema([Article.self, Highlight.self, Tag.self, Feed.self, FeedEntry.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Pre-existing subscription to r/swift.
        let existing = Feed(feedURL: URL(string: "https://www.reddit.com/r/swift/.rss")!)
        context.insert(existing)
        try context.save()

        let subs = [
            RedditSubreddit(id: "t5_1", name: "swift", title: "Swift", subscribers: 1),
            RedditSubreddit(id: "t5_2", name: "ios", title: "iOS", subscribers: 2),
        ]
        let created = RedditImporter.subscribe(to: subs, context: context)
        XCTAssertEqual(created, 1, "r/swift already subscribed; only r/ios is new")

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let urls = Set(feeds.compactMap { $0.feedURL?.absoluteString })
        XCTAssertTrue(urls.contains("https://www.reddit.com/r/ios/.rss"))
        let ios = try XCTUnwrap(feeds.first { $0.feedURL?.absoluteString.contains("/r/ios/") == true })
        XCTAssertEqual(ios.title, "r/ios")
    }

    // MARK: - JSON fixture helpers

    private static func listing(children: String, after: String?) -> String {
        let afterJSON = after.map { "\"\($0)\"" } ?? "null"
        return #"{"kind":"Listing","data":{"after":\#(afterJSON),"children":[\#(children)]}}"#
    }

    private static func listing(children: [String], after: String?) -> String {
        listing(children: children.joined(separator: ","), after: after)
    }

    private static func subredditChild(name: String, display: String) -> String {
        #"{"kind":"t5","data":{"name":"\#(name)","display_name":"\#(display)","title":"\#(display)","subscribers":10}}"#
    }

    private static func linkChild(name: String, title: String, url: String?, isSelf: Bool) -> String {
        let urlJSON = url.map { "\"\($0)\"" } ?? "null"
        let permalink = "/r/x/comments/\(name.replacingOccurrences(of: "t3_", with: ""))/slug/"
        return #"{"kind":"t3","data":{"name":"\#(name)","title":"\#(title)","url":\#(urlJSON),"permalink":"\#(permalink)","is_self":\#(isSelf),"selftext_html":null,"subreddit":"x"}}"#
    }

    private static func commentChild() -> String {
        #"{"kind":"t1","data":{"body":"a comment","id":"c1"}}"#
    }

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Test doubles

/// Fixed-token provider so the client's request plumbing runs without a real
/// OAuth token or Keychain.
private struct MockTokenProvider: RedditTokenProviding {
    func validAccessToken() async throws -> String { "tok" }
    func forceRefresh() async throws -> String { "tok" }
}

/// URLProtocol stub that answers requests from a per-test handler. Lets the real
/// `RedditAPIClient` pagination loop run over canned pages with no network.
final class StubURLProtocol: URLProtocol {
    /// (statusCode, headers, body) for a given request. Set per test.
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
