import SwiftUI

/// What layer 1 — the group/list card — is currently showing. This is the
/// app's whole top-level navigation; there is no tab bar behind it any more
/// (issue #57).
enum SidebarDestination: Hashable {
    case library
    case allItems
    case feed(Feed)
    case highlights
    case search
}

/// How a subscription is grouped in the sidebar. Derived from the feed's URLs
/// — no schema change, no new stored state. Pure so it is unit-testable
/// (see `SidebarFeedGroupingTests`).
enum FeedSourceKind: String, CaseIterable, Identifiable {
    case youtube
    case reddit
    case web

    var id: String { rawValue }

    /// Section header in the sidebar.
    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .reddit:  return "Reddit"
        case .web:     return "Websites"
        }
    }

    var systemImage: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .reddit:  return "bubble.left.and.bubble.right.fill"
        case .web:     return "globe"
        }
    }

    /// Source identity hue (§2.2 / BR5). Row and kind identity only — it never
    /// tints text, selection, controls or `Accent.*`. Normalised to our chip
    /// lightness so the three read as siblings in one column rather than a
    /// logo parade.
    var tint: Color {
        switch self {
        case .youtube: return Source.youtube
        case .reddit:  return Source.reddit
        case .web:     return Source.website
        }
    }

    /// Display order of the groups, YouTube first (matching Reader's grouping
    /// of the loudest media type at the top).
    static let displayOrder: [FeedSourceKind] = [.youtube, .reddit, .web]

    /// Classifies a subscription by looking at its feed/site URLs. Reddit wins
    /// over YouTube only because the two host sets are disjoint; anything we
    /// don't recognise is a plain website/RSS subscription.
    static func kind(feedURL: URL?, siteURL: URL?) -> FeedSourceKind {
        if RedditFeed.isRedditURL(feedURL) || RedditFeed.isRedditURL(siteURL) {
            return .reddit
        }
        if YouTubeURL.isYouTubeHost(feedURL?.host) || YouTubeURL.isYouTubeHost(siteURL?.host) {
            return .youtube
        }
        return .web
    }

    static func kind(for feed: Feed) -> FeedSourceKind {
        kind(feedURL: feed.feedURL, siteURL: feed.siteURL)
    }
}

extension Feed {
    /// Title fallback chain shared by the sidebar rows and the feed container's
    /// navigation title.
    var sidebarDisplayTitle: String {
        if !title.isEmpty { return title }
        if let host = siteURL?.host ?? feedURL?.host { return host }
        return "Feed"
    }
}
