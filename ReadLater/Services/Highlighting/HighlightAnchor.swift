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

    static func locate(
        in text: String,
        startOffset: Int,
        endOffset: Int,
        quotedText: String
    ) -> Located? {
        guard !text.isEmpty, !quotedText.isEmpty else { return nil }
        let ns = text as NSString

        // Fast path: stored offsets still match the quoted text verbatim.
        if startOffset >= 0, endOffset <= ns.length, startOffset < endOffset {
            let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)
            if ns.substring(with: nsRange) == quotedText, let r = Range(nsRange, in: text) {
                return Located(range: r, startOffset: startOffset, endOffset: endOffset, wasRepaired: false)
            }
        }

        // Re-anchor: find quotedText verbatim.
        let found = ns.range(of: quotedText)
        if found.location != NSNotFound, let r = Range(found, in: text) {
            return Located(
                range: r,
                startOffset: found.location,
                endOffset: found.location + found.length,
                wasRepaired: true
            )
        }

        // Whitespace-collapsed fallback for reflowed articles (spaces became
        // newlines or runs of whitespace changed length).
        return locateCollapsed(in: text, quotedText: quotedText)
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
