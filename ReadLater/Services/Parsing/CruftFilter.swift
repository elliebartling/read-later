import Foundation

/// Pure block-level cruft filter (Layer B of docs/parser-cruft-design.md).
///
/// Runs over the typed `[ArticleBlock]` produced by `ArticleParser` at parse
/// time — first ingest and explicit Re-extract only. It must NEVER run against
/// an already-saved article's stored blocks, because `plainText` derived from
/// the filtered blocks is the UTF-16 highlight offset space: re-filtering
/// stored text would shift every highlight after a removed block.
///
/// Design rules (precision over recall):
/// - Phrase rules fire only on blocks of ≤ `CruftRules.phraseMaxWords` words.
/// - Auth/social exact rules require the *entire* normalized block to match,
///   and never fire on headings.
/// - Social matches are additionally cluster-gated: removed only when the
///   block is a list item or an adjacent block also matched a rule.
/// - If filtering would leave no text-bearing content at all, the original
///   blocks are returned untouched (never nuke an article to empty).
enum CruftFilter {

    struct Result {
        /// Blocks that survive — the parser derives `plainText` from these.
        let kept: [ArticleBlock]
        /// Blocks removed as cruft, in document order. Not persisted today;
        /// returned so a future "Show removed content" escape hatch can keep
        /// them without reshaping this API.
        let removed: [ArticleBlock]
    }

    /// Why a block matched. Internal for tests.
    enum Match {
        case phrase, auth, social, metadata
    }

    static func filter(_ blocks: [ArticleBlock]) -> Result {
        // Pass 1: classify every block independently.
        let matches: [Match?] = blocks.map { classify($0) }

        // Pass 2: decide removals. Social is cluster-gated; everything else
        // that matched is removed outright.
        var remove = [Bool](repeating: false, count: blocks.count)
        for (i, match) in matches.enumerated() {
            guard let match else { continue }
            switch match {
            case .phrase, .auth, .metadata:
                remove[i] = true
            case .social:
                let isListItem = blocks[i].type == .listItem
                let prevMatched = i > 0 && matches[i - 1] != nil
                let nextMatched = i + 1 < matches.count && matches[i + 1] != nil
                remove[i] = isListItem || prevMatched || nextMatched
            }
        }

        var kept: [ArticleBlock] = []
        var removed: [ArticleBlock] = []
        for (i, block) in blocks.enumerated() {
            if remove[i] { removed.append(block) } else { kept.append(block) }
        }

        // Safety valve: never filter an article down to zero text content.
        let keptHasText = kept.contains { $0.type.isTextBearing && !($0.text ?? "").isEmpty }
        let originalHadText = blocks.contains { $0.type.isTextBearing && !($0.text ?? "").isEmpty }
        if originalHadText, !keptHasText {
            return Result(kept: blocks, removed: [])
        }
        return Result(kept: kept, removed: removed)
    }

    // MARK: - Classification

    /// Classifies a single block against the rule tables. Nil = not cruft.
    /// Internal (not private) so unit tests can probe individual rules.
    static func classify(_ block: ArticleBlock) -> Match? {
        guard block.type.isTextBearing, let raw = block.text, !raw.isEmpty else {
            return nil
        }
        // Preformatted blocks are code/verbatim — never treat as cruft.
        if block.type == .preformatted { return nil }

        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        let words = normalized.split(separator: " ").count

        // Metadata: anchored whole-block regexes (any block type).
        for pattern in CruftRules.metadataPatterns {
            if normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .metadata
            }
        }

        // Phrases: substring match, length-gated (any block type).
        if words <= CruftRules.phraseMaxWords {
            for fragment in CruftRules.phraseFragments where normalized.contains(fragment) {
                return .phrase
            }
        }

        // Exact rules never touch headings — "Sign in" can be a legitimate
        // section heading in a tutorial.
        guard block.type != .heading else { return nil }

        if words <= CruftRules.authExactMaxWords, CruftRules.authExact.contains(normalized) {
            return .auth
        }
        if CruftRules.socialExact.contains(normalized) {
            return .social
        }
        return nil
    }

    /// Lowercases, straightens curly apostrophes, collapses whitespace, and
    /// strips leading/trailing punctuation so "Sign in." and "Sign In"
    /// normalize identically. Interior punctuation is preserved ("member-only
    /// story" keeps its hyphen).
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading/trailing punctuation runs (·, →, ., !, quotes…).
        s = s.replacingOccurrences(
            of: #"^[\p{P}\p{S}\s]+|[\p{P}\p{S}\s]+$"#,
            with: "",
            options: .regularExpression
        )
        return s
    }
}
