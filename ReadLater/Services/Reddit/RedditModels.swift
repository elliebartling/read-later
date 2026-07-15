import Foundation

// MARK: - Domain models (what the rest of the app consumes)

/// The signed-in Reddit account (from the `identity` scope).
struct RedditAccount: Equatable {
    let name: String
}

/// A subreddit the user is subscribed to (from `mysubreddits`).
struct RedditSubreddit: Identifiable, Equatable {
    /// Fullname, e.g. `t5_2qh1i`. Stable identity for the picker list.
    let id: String
    /// Display name without the `r/` prefix, e.g. `swift`.
    let name: String
    /// Human title (`title` field), often the same as name.
    let title: String
    let subscribers: Int?

    /// The subreddit's Atom feed URL — the wave-1 subscribe surface. Built from
    /// the name so no extra network call is needed.
    var feedURL: URL? {
        RedditFeed.normalizeSubredditShorthand("r/\(name)")
    }
}

/// A saved post materialized for import. Only link/self *posts* (`t3_…`) are
/// represented — saved comments (`t1_…`) are skipped (nothing article-shaped to
/// read).
struct RedditSavedPost: Identifiable, Equatable {
    /// Fullname, e.g. `t3_abc123`.
    let id: String
    let title: String
    /// For a link post, the external destination; for a self post, the reddit
    /// permalink URL. Matches the field's meaning in wave-1 `FeedEntry`.
    let url: URL?
    /// Absolute comments permalink (→ `Article.discussionURL`).
    let permalink: URL?
    let isSelf: Bool
    /// Decoded self-post body HTML (self posts only) for the prefetched-HTML
    /// parse path — the same routing wave-1 uses for Reddit self posts.
    let selfTextHTML: String?
    let subreddit: String?
}

// MARK: - Raw wire models (Reddit's `Listing`/`Thing` JSON)

/// Reddit wraps every listing in `{ "kind": "Listing", "data": { after, children } }`.
/// A saved listing mixes `Thing` kinds (`t3` links, `t1` comments), so each
/// child's `data` is decoded **tolerantly** (`try?`): a comment whose payload
/// doesn't satisfy `T`'s required fields yields `data == nil` instead of failing
/// the whole page. Callers filter by `kind` and use the non-nil `data`.
struct RedditListing<T: Decodable>: Decodable {
    let data: ListingData

    struct ListingData: Decodable {
        let after: String?
        let children: [Child]
    }

    struct Child: Decodable {
        let kind: String
        let data: T?

        enum CodingKeys: String, CodingKey { case kind, data }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            data = try? container.decode(T.self, forKey: .data)
        }
    }

    var children: [Child] { data.children }
    var after: String? { data.after }
}

/// `identity` response (`GET /api/v1/me`).
struct RedditAccountData: Decodable {
    let name: String
}

/// A subreddit `Thing`'s data (subset we use).
struct RedditSubredditData: Decodable {
    let name: String? // fullname, e.g. t5_...
    let displayName: String
    let title: String?
    let subscribers: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case title
        case subscribers
    }
}

/// A link `Thing`'s data (subset we use). Saved listings mix `t3` (links) and
/// `t1` (comments); only `t3` decodes into this.
struct RedditLinkData: Decodable {
    let name: String // fullname t3_...
    let title: String
    let url: String?
    let permalink: String?
    let isSelf: Bool?
    let selftextHTML: String?
    let subreddit: String?

    enum CodingKeys: String, CodingKey {
        case name
        case title
        case url
        case permalink
        case isSelf = "is_self"
        case selftextHTML = "selftext_html"
        case subreddit
    }
}

// MARK: - Pure transforms (unit-tested directly)

/// Pure helpers for turning Reddit wire data into domain models and deriving
/// fullnames. Network-free so pagination assembly, fullname derivation, and
/// self/link normalization are all testable with fixtures.
enum RedditParsing {

    /// Reddit HTML fields (`selftext_html`) arrive HTML-entity-encoded (`&lt;`).
    /// Decodes one level so the body renders through the prefetched-HTML path,
    /// mirroring how wave-1 handles feed `<content>`.
    static func decodeSelfTextHTML(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return FeedParser.decodeEntities(raw)
    }

    /// Maps a subreddit `Thing` to the domain model. Drops entries without a
    /// fullname (can't key them) — returns nil so `compactMap` filters them.
    static func subreddit(from data: RedditSubredditData) -> RedditSubreddit? {
        guard let fullname = data.name else { return nil }
        return RedditSubreddit(
            id: fullname,
            name: data.displayName,
            title: data.title ?? data.displayName,
            subscribers: data.subscribers
        )
    }

    /// Maps a saved link `Thing` to the import model, building an absolute
    /// permalink and choosing `url` the same way wave-1 does (external URL for
    /// link posts, the permalink for self posts).
    static func savedPost(from data: RedditLinkData) -> RedditSavedPost {
        let permalink = absolutePermalink(data.permalink)
        let isSelf = data.isSelf ?? false
        let resolvedURL: URL? = {
            if isSelf { return permalink }
            if let raw = data.url, let u = URL(string: raw) { return u }
            return permalink
        }()
        return RedditSavedPost(
            id: data.name,
            title: data.title,
            url: resolvedURL,
            permalink: permalink,
            isSelf: isSelf,
            selfTextHTML: isSelf ? decodeSelfTextHTML(data.selftextHTML) : nil,
            subreddit: data.subreddit
        )
    }

    /// Expands a relative permalink (`/r/sub/comments/…`) to an absolute
    /// reddit.com URL. Passes through already-absolute URLs.
    static func absolutePermalink(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        return URL(string: "https://\(RedditFeed.canonicalHost)\(raw)")
    }

    /// Derives a post fullname (`t3_<id>`) from a comments permalink of the form
    /// `…/comments/<id>/<slug>/`. Returns nil when the URL isn't a comments
    /// permalink. Used by the reader save-back, whose only handle on a post is
    /// its `discussionURL`.
    static func postFullname(fromPermalink url: URL) -> String? {
        let parts = url.pathComponents // ["/", "r", "sub", "comments", "<id>", ...]
        guard let idx = parts.firstIndex(of: "comments"), idx + 1 < parts.count else {
            return nil
        }
        let id = parts[idx + 1]
        guard !id.isEmpty else { return nil }
        return "t3_\(id)"
    }
}
