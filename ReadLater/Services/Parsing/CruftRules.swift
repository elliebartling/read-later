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
        // Press-release boilerplate (ScienceDaily et al.) — the "Story
        // Source:" VALUE line. Both fragments are wire-service phrasing that
        // essentially never occurs as article prose.
        "materials provided by",
        "content may be edited for style and length",
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

    /// Single tokens that make up share/follow button rows. A block of ≥ 3
    /// words where EVERY word (after per-word punctuation stripping) is one of
    /// these is a share row even when no `socialExact` entry matches the whole
    /// block — e.g. ScienceDaily's "Share: Facebook Twitter Pinterest LinkedIn
    /// Email" extracting as one paragraph. Removed outright (a ≥3-token
    /// all-social block is its own cluster).
    static let socialTokens: Set<String> = [
        "share", "tweet", "follow",
        "facebook", "twitter", "x", "pinterest", "linkedin", "reddit",
        "instagram", "whatsapp", "telegram",
        "email", "print",
    ]

    /// Minimum word count for the all-social-tokens row rule. One- and
    /// two-word blocks stay cluster-gated via `socialExact` so a lone "Share"
    /// paragraph in prose keeps surviving.
    static let socialRowMinWords = 3

    // MARK: - Metadata rules (category 4: whole-block regexes)

    /// Anchored, case-insensitive regexes matched against the normalized
    /// block. Whole-block only — "a 6 min read that changed me" is prose and
    /// does not match.
    static let metadataPatterns: [String] = [
        #"^\d+\s*min(ute)?s?\s*(read|listen)$"#,
        #"^\d+\s*free\s+(stor(y|ies)|articles?)\s+left$"#,
        #"^[\d.,]+[km]?\s*followers$"#,
        // Engagement counts with their unit attached ("47 responses",
        // "3.6K claps") — whole-block, unit makes them unambiguous.
        #"^[\d.,]+[km]?\s*(responses?|claps?|comments?|likes?|reactions?)$"#,
    ]

    // MARK: - Engagement counter rules (category 6: bare-count blocks)

    /// Medium's post-content engagement furniture extracts as standalone
    /// paragraphs of bare counts: "3.6K", "2", "1", "1"… Whole-block matches
    /// for a bare number or a K/M/B-suffixed count. DANGEROUS in isolation —
    /// a listicle paragraph that is just "42" is real content — so pass 2
    /// gates these hard: paragraphs only (a "1." listicle heading and bare
    /// numeric list items are exempt), and removed only when clustered with
    /// other cruft, with the pure-counter-run case additionally confined to
    /// the article's tail (`counterTailBlocks`). A mid-article dramatic
    /// "3" / "2" / "1" countdown survives; the end-of-article clap stack dies.
    static let counterPatterns: [String] = [
        #"^\d{1,4}(,\d{3})*$"#,
        #"^\d+(\.\d+)?[kmb]$"#,
    ]

    /// A run of pure counters (no non-counter cruft adjacent) is only removed
    /// within this many blocks of the end of the article.
    static let counterTailBlocks = 12

    // MARK: - Label/value metadata rules (category 5: press-release furniture)

    /// The ScienceDaily-style pattern: a short label block ending in ":" with
    /// its value in the NEXT block ("Date:" / "July 14, 2026"). The colon is
    /// required on the RAW text — a legit "Summary" section heading (no colon)
    /// never matches — and, unlike the exact auth/social rules, headings are
    /// NOT exempt for this family: aggregators emit these labels as headings.
    static let labelMaxWords = 4

    /// Field labels whose short, non-sentential VALUE block is consumed along
    /// with the label ("Date:" + "July 14, 2026"; "Source:" + "University of
    /// Michigan"). A long or sentence-like follower is kept: only the label
    /// falls.
    static let fieldLabels: Set<String> = [
        "date", "source", "sources",
        "updated", "last updated", "published", "posted",
    ]

    /// Maximum word count for a consumed value block, and it must not read as
    /// a sentence (no interior ". ", no terminal ./!/?).
    static let valueMaxWords = 8

    /// Labels removed ALONE — their value is real prose that must survive.
    /// Decision (docs/parser-cruft-design.md, round 2): ScienceDaily's
    /// "Summary:" duplicates the abstract; the abstract is content the user
    /// may want to read/highlight, so we drop only the label. "Story Source:"
    /// and "Journal Reference:" values are handled separately: the
    /// story-source boilerplate falls to the "materials provided by" phrase
    /// rule, and journal citations are deliberately KEPT (scholarly value;
    /// precision over recall).
    static let labelOnly: Set<String> = [
        "summary",
        "story source", "story sources",
        "journal reference", "journal references",
        "cite this page", "cite this article",
        "share", "follow us",
    ]

    /// Whole-block section furniture, matched with or without a trailing
    /// colon, headings included — these are exactly the headings we want gone.
    /// Deliberately specific strings; generic words never belong here.
    static let sectionFurniture: Set<String> = [
        "full story",
        "related stories",
        "related terms",
        "related topics",
        "explore more from sciencedaily",
        "trending at scitechdaily.com",
        "breaking this hour",
        "strange & offbeat",
        "advertisement",
        // Medium highlight-engagement furniture.
        "top highlight",
    ]
}
