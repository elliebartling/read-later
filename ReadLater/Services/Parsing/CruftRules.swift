import Foundation

/// Rule tables for `CruftFilter`. Kept as plain data (no logic) so adding a
/// site's nag phrase is a one-line diff with an accompanying fixture test.
///
/// Precision over recall: every entry here should be copy that essentially
/// never appears as *article prose*. When in doubt, leave it out — cruft that
/// slips through is an annoyance; eaten content is data loss.
///
/// See docs/parser-cruft-design.md for the taxonomy these tables implement.
enum CruftRules {

    // MARK: - Phrase rules (category 1: named-vendor + generic nags)

    /// Case-insensitive substring match against a normalized block, but only
    /// when the whole block is at most `phraseMaxWords` words. The length gate
    /// keeps a long prose paragraph that *quotes* a nag from being eaten.
    static let phraseMaxWords = 25

    static let phraseFragments: [String] = [
        // Medium
        "join medium for free",
        "stories in your inbox",
        "member-only story",
        "remember me for faster sign in",
        "get updates from this writer",
        "read member-only stories",
        // Substack / generic newsletter
        "subscribe to our newsletter",
        "subscribe to my newsletter",
        "sign up for our newsletter",
        "sign up for my newsletter",
        "subscribe for free to receive",
        "type your email",
        "enter your email",
        "no spam, unsubscribe",
        // Generic membership / paywall nags
        "become a member",
        "become a paid subscriber",
        "create a free account",
        "already have an account",
        "this post is for paid subscribers",
        "upgrade to paid",
    ]

    // MARK: - Auth CTA rules (category 2: exact short blocks)

    /// Whole-block, case-insensitive exact match after normalization
    /// (punctuation-stripped, whitespace-collapsed). Bounded by
    /// `authExactMaxWords` by construction — every entry is short. A real
    /// sentence *containing* "sign in" never matches because these require the
    /// entire block to equal the entry. Headings are exempt (a tutorial's
    /// "Sign in" section heading is content).
    static let authExactMaxWords = 6

    static let authExact: Set<String> = [
        "sign in",
        "sign up",
        "log in",
        "login",
        "sign in with google",
        "sign in with apple",
        "sign in with facebook",
        "sign in with email",
        "sign up with google",
        "sign up with apple",
        "sign up with facebook",
        "sign up with email",
        "continue with google",
        "continue with apple",
        "continue with facebook",
        "continue with email",
        "remember me",
        "forgot password",
        "forgot your password",
        "create account",
        "create an account",
    ]

    // MARK: - Social CTA rules (category 3: cluster-gated exact blocks)

    /// Whole-block exact matches that are only removed when *clustered* — the
    /// block is a list item, or an adjacent block also matched a cruft rule.
    /// A lone "Share." paragraph in running prose survives; a follow/share
    /// button row (which extracts as consecutive short blocks or list items)
    /// does not.
    static let socialExact: Set<String> = [
        "share",
        "tweet",
        "follow",
        "follow us",
        "follow us on twitter",
        "follow us on instagram",
        "copy link",
        "share this article",
        "share this post",
        "share on twitter",
        "share on facebook",
        "share on linkedin",
        "facebook",
        "twitter",
        "linkedin",
        "reddit",
        "instagram",
        "pinterest",
        "whatsapp",
        "telegram",
    ]

    // MARK: - Metadata rules (category 4: whole-block regexes)

    /// Anchored, case-insensitive regexes matched against the normalized
    /// block. Whole-block only — "a 6 min read that changed me" is prose and
    /// does not match.
    static let metadataPatterns: [String] = [
        #"^\d+\s*min(ute)?s?\s*(read|listen)$"#,
        #"^\d+\s*free\s+(stor(y|ies)|articles?)\s+left$"#,
        #"^[\d.,]+[km]?\s*followers$"#,
    ]
}
