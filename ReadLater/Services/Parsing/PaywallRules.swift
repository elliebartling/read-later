import Foundation

/// Rule tables for `PaywallDetector`. Kept as plain data (no logic) so adding a
/// site's gate marker is a one-line diff with an accompanying fixture test.
///
/// Precision over recall (same discipline as `CruftRules`): every entry here
/// should be copy or metadata that essentially only appears on a metered /
/// member-only gate, never in ordinary article prose. A false positive here
/// mislabels a fully-readable article as "preview only"; when in doubt, leave
/// it out.
enum PaywallRules {

    // MARK: - Truncation heuristic

    /// Word floor above which an extraction counts as "substantially more than
    /// a preview" (`PaywallDetector.verdict`). schema.org
    /// `isAccessibleForFree:false` describes the article's *public*
    /// accessibility and stays false forever — even when an authenticated fetch
    /// returned the complete text — so that signal alone flags an article only
    /// when the captured content is below this scale.
    ///
    /// Why 500: Medium-style anonymous previews are the intro section, in
    /// practice well under ~350 words; member-only long-form is typically
    /// 1000+. 500 is also 10x the quality gate's 50-word minimum, i.e. "passed
    /// the gate comfortably". A sub-500-word *complete* member article with no
    /// gate CTA on the page is the accepted false-positive cost (rare, and the
    /// banner is advisory — the flag recomputes on every re-extract).
    static let substantialWordFloor = 500

    // MARK: - schema.org signal

    /// schema.org property whose false value marks metered/member-only content.
    /// Publishers emit it inside a `<script type="application/ld+json">` blob,
    /// often nested in an `@graph` array. Value forms seen in the wild: the JSON
    /// boolean `false`, or the strings `"False"` / `"http://schema.org/False"`.
    static let accessibleForFreeKey = "isAccessibleForFree"

    // MARK: - In-DOM gate markers (category: registration / paywall walls)

    /// Case-insensitive substring markers matched against the rendered page's
    /// visible text. These are the calls-to-action a wall shows in place of the
    /// article body once the free preview runs out — sites render them only on
    /// gated (anonymous / expired-session) views, so their presence is direct
    /// evidence the capture is truncated. Kept tight and gate-specific so they
    /// don't fire on prose that merely mentions subscribing.
    static let gatePhrases: [String] = [
        // Medium
        "read the full story",
        "create an account to read the full story",
        "sign up to read the full story",
        "sign in to read the full story",
        // Generic membership / metered walls
        "this story is only available to members",
        "this post is for paying subscribers",
        "this post is for paid subscribers",
        "subscribe to keep reading",
        "subscribe to continue reading",
        "to continue reading this article",
        "to read the rest of this story",
        "become a member to read this",
        "you've reached your free article limit",
        "you have reached your free article limit",
    ]
}
