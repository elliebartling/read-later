import Foundation

/// Locates a highlight's character range inside a body of plain text.
///
/// The primary anchor is (startOffset, endOffset). If those still line up with
/// `quotedText` we use them as-is. If they don't (e.g. the article was
/// re-parsed and text shifted), we fall back to searching for `quotedText` and
/// return the updated offsets.
enum HighlightAnchor {

    struct Located {
        let range: Range<String.Index>
        let startOffset: Int
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

        if startOffset >= 0, endOffset <= text.count, startOffset < endOffset {
            let start = text.index(text.startIndex, offsetBy: startOffset)
            let end = text.index(text.startIndex, offsetBy: endOffset)
            if String(text[start..<end]) == quotedText {
                return Located(range: start..<end,
                               startOffset: startOffset,
                               endOffset: endOffset,
                               wasRepaired: false)
            }
        }

        // Fuzzy re-anchor: find quotedText verbatim first, then loosen if needed.
        if let r = text.range(of: quotedText) {
            let start = text.distance(from: text.startIndex, to: r.lowerBound)
            let end = text.distance(from: text.startIndex, to: r.upperBound)
            return Located(range: r, startOffset: start, endOffset: end, wasRepaired: true)
        }

        // Whitespace-collapsed fallback for reflowed articles.
        let normalizedQuote = collapseWhitespace(quotedText)
        let normalizedText = collapseWhitespace(text)
        guard let normRange = normalizedText.range(of: normalizedQuote) else { return nil }

        let normStart = normalizedText.distance(from: normalizedText.startIndex, to: normRange.lowerBound)
        let normEnd = normalizedText.distance(from: normalizedText.startIndex, to: normRange.upperBound)

        guard let (rawStart, rawEnd) = mapNormalizedRangeToRaw(text: text, normStart: normStart, normEnd: normEnd) else {
            return nil
        }
        let start = text.index(text.startIndex, offsetBy: rawStart)
        let end = text.index(text.startIndex, offsetBy: rawEnd)
        return Located(range: start..<end, startOffset: rawStart, endOffset: rawEnd, wasRepaired: true)
    }

    /// Walks the raw text and the normalized text in lock-step to translate a
    /// (normStart, normEnd) window back to raw offsets.
    private static func mapNormalizedRangeToRaw(text: String, normStart: Int, normEnd: Int) -> (Int, Int)? {
        var rawIndex = 0
        var normIndex = 0
        var rawStart = -1
        var rawEnd = -1
        var lastWasSpace = false

        for scalar in text.unicodeScalars {
            let isSpace = scalar.properties.isWhitespace || scalar == "\n"
            let contributes: Bool
            if isSpace {
                contributes = !lastWasSpace
                lastWasSpace = true
            } else {
                contributes = true
                lastWasSpace = false
            }

            if contributes && normIndex == normStart && rawStart == -1 {
                rawStart = rawIndex
            }
            if contributes {
                normIndex += 1
            }
            rawIndex += 1
            if normIndex == normEnd && rawEnd == -1 {
                rawEnd = rawIndex
                break
            }
        }
        guard rawStart >= 0, rawEnd > rawStart else { return nil }
        return (rawStart, rawEnd)
    }

    private static func collapseWhitespace(_ s: String) -> String {
        var out = ""
        var lastWasSpace = false
        for scalar in s.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "\n" {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
