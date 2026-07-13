import Foundation

/// Locates a highlight's range inside a body of plain text.
///
/// All offsets are UTF-16 code units — the same unit as
/// `UITextView.selectedRange` (NSRange), which is where they originate.
/// Interpreting them as Swift `Character` offsets silently misplaces
/// highlights in any article containing emoji or other non-BMP characters.
///
/// The primary anchor is (startOffset, endOffset). If those still line up with
/// `quotedText` we use them as-is. If they don't (e.g. the article was
/// re-parsed and text shifted), we fall back to searching for `quotedText` and
/// return the updated offsets.
enum HighlightAnchor {

    struct Located {
        let range: Range<String.Index>
        /// UTF-16 units
        let startOffset: Int
        /// UTF-16 units
        let endOffset: Int
        let wasRepaired: Bool
    }

    /// Re-anchoring cascade (in priority order):
    ///   1. exact stored offsets whose text still matches `quotedText`,
    ///   2. quote + context: among every occurrence of `quotedText`, prefer one
    ///      whose immediately-preceding text ends with `prefixContext` and/or
    ///      whose following text starts with `suffixContext` (both matching beats
    ///      one; ties broken by proximity to the stale offset),
    ///   3. quote alone: the occurrence whose start is NEAREST the stale offset,
    ///   4. whitespace-collapsed fallback for reflowed articles.
    ///
    /// `prefixContext`/`suffixContext` default to nil so existing call sites keep
    /// compiling; when both are nil the cascade skips straight from step 1 to
    /// step 3 (nearest occurrence).
    static func locate(
        in text: String,
        startOffset: Int,
        endOffset: Int,
        quotedText: String,
        prefixContext: String? = nil,
        suffixContext: String? = nil
    ) -> Located? {
        guard !text.isEmpty, !quotedText.isEmpty else { return nil }
        let ns = text as NSString

        // 1. Fast path: stored offsets still match the quoted text verbatim.
        if startOffset >= 0, endOffset <= ns.length, startOffset < endOffset {
            let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)
            if ns.substring(with: nsRange) == quotedText, let r = Range(nsRange, in: text) {
                return Located(range: r, startOffset: startOffset, endOffset: endOffset, wasRepaired: false)
            }
        }

        // Enumerate every verbatim occurrence once; steps 2 & 3 choose among them.
        let occurrences = allOccurrences(of: quotedText, in: ns)
        if !occurrences.isEmpty {
            // 2. quote + context.
            if let best = bestContextMatch(
                occurrences: occurrences,
                ns: ns,
                prefixContext: prefixContext,
                suffixContext: suffixContext,
                startOffset: startOffset
            ), let r = Range(best, in: text) {
                return Located(
                    range: r,
                    startOffset: best.location,
                    endOffset: best.location + best.length,
                    wasRepaired: true
                )
            }

            // 3. quote alone, nearest to the stale start offset.
            let nearest = occurrences.min {
                abs($0.location - startOffset) < abs($1.location - startOffset)
            }
            if let nearest, let r = Range(nearest, in: text) {
                return Located(
                    range: r,
                    startOffset: nearest.location,
                    endOffset: nearest.location + nearest.length,
                    wasRepaired: true
                )
            }
        }

        // 4. Whitespace-collapsed fallback for reflowed articles (spaces became
        // newlines or runs of whitespace changed length).
        return locateCollapsed(in: text, quotedText: quotedText)
    }

    /// Captures up to 32 UTF-16 units of context on each side of `range` within
    /// `text`, for later disambiguation. The windows are expanded outward to
    /// composed-character-sequence boundaries so a surrogate pair or combining
    /// sequence straddling the 32-unit edge is never split (the returned strings
    /// may therefore be a couple of units longer than 32). Returns nil for a
    /// side with no surrounding text.
    static func contextAround(range: NSRange, in text: String) -> (prefix: String?, suffix: String?) {
        let ns = text as NSString
        let maxContext = 32
        guard range.location >= 0, range.length >= 0,
              range.location + range.length <= ns.length else {
            return (nil, nil)
        }

        var prefix: String?
        if range.location > 0 {
            let start = max(0, range.location - maxContext)
            var prefixRange = NSRange(location: start, length: range.location - start)
            prefixRange = ns.rangeOfComposedCharacterSequences(for: prefixRange)
            let s = ns.substring(with: prefixRange)
            prefix = s.isEmpty ? nil : s
        }

        var suffix: String?
        let end = range.location + range.length
        if end < ns.length {
            let available = ns.length - end
            let len = min(maxContext, available)
            var suffixRange = NSRange(location: end, length: len)
            suffixRange = ns.rangeOfComposedCharacterSequences(for: suffixRange)
            let s = ns.substring(with: suffixRange)
            suffix = s.isEmpty ? nil : s
        }

        return (prefix, suffix)
    }

    /// Every verbatim, non-overlapping occurrence of `quote` in `ns`.
    private static func allOccurrences(of quote: String, in ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        guard (quote as NSString).length > 0 else { return result }
        var searchStart = 0
        while searchStart <= ns.length {
            let searchRange = NSRange(location: searchStart, length: ns.length - searchStart)
            let found = ns.range(of: quote, options: [], range: searchRange)
            if found.location == NSNotFound { break }
            result.append(found)
            searchStart = found.location + max(found.length, 1)
        }
        return result
    }

    /// Among `occurrences`, the one best matching the captured context. Scores
    /// each occurrence by how many of the provided (non-empty) contexts match its
    /// surroundings; the highest score wins, ties broken by proximity to
    /// `startOffset`. Returns nil when no context is provided or nothing matches.
    private static func bestContextMatch(
        occurrences: [NSRange],
        ns: NSString,
        prefixContext: String?,
        suffixContext: String?,
        startOffset: Int
    ) -> NSRange? {
        let prefix = (prefixContext?.isEmpty == false) ? prefixContext : nil
        let suffix = (suffixContext?.isEmpty == false) ? suffixContext : nil
        guard prefix != nil || suffix != nil else { return nil }

        var best: NSRange?
        var bestScore = 0
        for occ in occurrences {
            var score = 0
            if let prefix {
                let preceding = ns.substring(to: occ.location)
                if preceding.hasSuffix(prefix) { score += 1 }
            }
            if let suffix {
                let following = ns.substring(from: occ.location + occ.length)
                if following.hasPrefix(suffix) { score += 1 }
            }
            if score == 0 { continue }
            if score > bestScore {
                bestScore = score
                best = occ
            } else if score == bestScore, let current = best,
                      abs(occ.location - startOffset) < abs(current.location - startOffset) {
                best = occ
            }
        }
        return best
    }

    private static func locateCollapsed(in text: String, quotedText: String) -> Located? {
        let collapsedQuote = collapseWhitespace(quotedText)
        let collapsedText = collapseWhitespace(text)
        guard !collapsedQuote.isEmpty else { return nil }

        let collapsedNS = collapsedText as NSString
        let found = collapsedNS.range(of: collapsedQuote)
        guard found.location != NSNotFound else { return nil }

        guard let (rawStart, rawEnd) = mapCollapsedRangeToRaw(
            text: text,
            collapsedStart: found.location,
            collapsedEnd: found.location + found.length
        ) else { return nil }

        let nsRange = NSRange(location: rawStart, length: rawEnd - rawStart)
        guard let r = Range(nsRange, in: text) else { return nil }
        return Located(range: r, startOffset: rawStart, endOffset: rawEnd, wasRepaired: true)
    }

    /// Walks raw and collapsed text in lock-step (both measured in UTF-16
    /// units) to translate a collapsed-space window back to raw offsets.
    /// Collapsing rules mirror collapseWhitespace: each whitespace run
    /// contributes exactly one unit (a single space); other scalars contribute
    /// their own UTF-16 width.
    private static func mapCollapsedRangeToRaw(text: String, collapsedStart: Int, collapsedEnd: Int) -> (Int, Int)? {
        var rawU16 = 0
        var collapsedU16 = 0
        var rawStart = -1
        var rawEnd = -1
        var lastWasSpace = false

        for scalar in text.unicodeScalars {
            let isSpace = scalar.properties.isWhitespace
            let contributed: Int
            if isSpace {
                contributed = lastWasSpace ? 0 : 1 // whole run collapses to one space
                lastWasSpace = true
            } else {
                contributed = UTF16.width(scalar)
                lastWasSpace = false
            }

            if contributed > 0, collapsedU16 == collapsedStart, rawStart == -1 {
                rawStart = rawU16
            }
            collapsedU16 += contributed
            rawU16 += UTF16.width(scalar)
            if collapsedU16 >= collapsedEnd, rawEnd == -1 {
                rawEnd = rawU16
                break
            }
        }
        guard rawStart >= 0, rawEnd > rawStart else { return nil }
        return (rawStart, rawEnd)
    }

    /// Collapses every whitespace run (spaces, newlines, tabs) to a single
    /// space. Deliberately does NOT trim — trimming would shift offsets and
    /// break mapCollapsedRangeToRaw's lock-step walk.
    private static func collapseWhitespace(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var lastWasSpace = false
        for scalar in s.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return out
    }
}
