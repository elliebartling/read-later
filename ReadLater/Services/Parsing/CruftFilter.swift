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
        /// Standalone label or section furniture ("Summary:", "FULL STORY",
        /// "RELATED STORIES") — removed alone, headings included.
        case label
        /// Field label ("Date:", "Source:") — removed, and the immediately
        /// following block is consumed too when it is a short, non-sentential
        /// value (a date, an org name).
        case fieldLabel
        /// Bare engagement count ("3.6K", "2") — candidate only; pass 2
        /// removes it solely when clustered with other cruft, and a
        /// pure-counter run additionally only in the article's tail.
        case counter
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
            case .phrase, .auth, .metadata, .label:
                remove[i] = true
            case .fieldLabel:
                remove[i] = true
                // Consume the immediately following block when it reads as a
                // short label VALUE (a date, an org name) rather than prose.
                // Only the direct successor — never skip past images or other
                // blocks looking for one.
                if i + 1 < blocks.count, isConsumableValue(blocks[i + 1]) {
                    remove[i + 1] = true
                }
            case .social:
                let isListItem = blocks[i].type == .listItem
                let prevMatched = i > 0 && matches[i - 1] != nil
                let nextMatched = i + 1 < matches.count && matches[i + 1] != nil
                remove[i] = isListItem || prevMatched || nextMatched
            case .counter:
                // A counter falls only when clustered: next to NON-counter
                // cruft anywhere, or next to any cruft when the block sits in
                // the article's tail (Medium's end-of-article clap stack).
                // A lone "42" listicle paragraph has no matched neighbors and
                // survives everywhere; a mid-article "3"/"2"/"1" countdown is
                // a pure-counter run outside the tail and survives too.
                let prev = i > 0 ? matches[i - 1] : nil
                let next = i + 1 < matches.count ? matches[i + 1] : nil
                let neighborMatched = prev != nil || next != nil
                let neighborNonCounter = (prev != nil && prev != .counter)
                    || (next != nil && next != .counter)
                let inTail = i >= max(0, blocks.count - CruftRules.counterTailBlocks)
                remove[i] = neighborNonCounter || (inTail && neighborMatched)
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

        // Label/value press-release furniture (category 5). Headings are NOT
        // exempt for this family — aggregators emit "RELATED STORIES" etc. as
        // headings. Field/standalone labels require the RAW text to end with
        // ":" so a legit colon-less "Summary" section heading never matches;
        // section furniture matches with or without the colon.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":"),
           words <= CruftRules.labelMaxWords {
            if CruftRules.fieldLabels.contains(normalized) { return .fieldLabel }
            if CruftRules.labelOnly.contains(normalized) { return .label }
        }
        if CruftRules.sectionFurniture.contains(normalized) { return .label }

        // A block of ≥ socialRowMinWords words that are ALL social tokens is a
        // share/follow row even as a single paragraph ("Share: Facebook
        // Twitter Pinterest LinkedIn Email") — it is its own cluster, so it
        // skips the adjacency gate. Headings stay exempt below.
        if block.type != .heading, words >= CruftRules.socialRowMinWords {
            let tokens = normalized.split(separator: " ").map {
                $0.trimmingCharacters(in: .punctuationCharacters)
            }
            if tokens.allSatisfy({ CruftRules.socialTokens.contains($0) }) {
                return .label
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

        // Bare engagement counters: PARAGRAPHS only — a "1." listicle heading
        // normalizes to "1" (heading, already exempt above) and a bare-number
        // list item (lottery numbers, table-ish data) must never match.
        if block.type == .paragraph {
            for pattern in CruftRules.counterPatterns {
                if normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    return .counter
                }
            }
        }
        return nil
    }

    /// True when `block` reads as a short label VALUE — a date or an org name
    /// — rather than prose: text-bearing, not a heading, at most
    /// `CruftRules.valueMaxWords` words, and non-sentential (no interior
    /// ". ", no terminal ./!/?).
    static func isConsumableValue(_ block: ArticleBlock) -> Bool {
        guard block.type.isTextBearing, block.type != .heading,
              let raw = block.text, !raw.isEmpty else { return false }
        let normalized = normalize(raw)
        let words = normalized.split(separator: " ").count
        guard words > 0, words <= CruftRules.valueMaxWords else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(". ") { return false }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return false
        }
        return true
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
