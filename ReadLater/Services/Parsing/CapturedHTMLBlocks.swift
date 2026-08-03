import Foundation

/// Pure HTML-fragment → `[ArticleBlock]` conversion, used as the **captured-
/// content floor**: when we already hold an item's body in hand (a Reddit self
/// post's `contentHTML` from the RSS entry, or `selftext_html` from the API),
/// a parse must never end in `.failed`.
///
/// Why a floor is needed at all: the captured body goes through
/// `ArticleParser.parse(url:prefetchedHTML:)`, which runs Readability over it.
/// Readability is built for full pages and gives up on a short fragment — its
/// character threshold is 500 — so a short self post (the majority of them:
/// a question, a link with a sentence of context) reliably parsed to nothing
/// and landed on "Couldn't parse this page" even though the post body was
/// sitting right there in the entry.
///
/// This walker is deliberately dumber than `__rlWalk`: no scoring, no cruft
/// heuristics, no container selection. It keeps every block-level chunk in
/// document order, because for captured content there is nothing to separate
/// article from chrome — the fragment IS the article. The one thing it does
/// remove is the syndication footer the source appends to every item
/// ("submitted by /u/name [link] [comments]"), via the shared
/// `CruftFilter.strippingTrailingBoilerplate` rules.
///
/// Pure and `nonisolated` throughout, so every branch is unit-testable from a
/// captured fixture without a WKWebView.
enum CapturedHTMLBlocks {

    /// Block-level element → block type. Anything not listed is inline and its
    /// text simply flows into the enclosing block.
    private static func blockKind(_ tag: String) -> (type: BlockType, level: Int?)? {
        switch tag {
        case "p", "div", "section", "article", "main", "td", "th", "dd", "dt":
            return (.paragraph, nil)
        case "h1": return (.heading, 1)
        case "h2": return (.heading, 2)
        case "h3": return (.heading, 3)
        case "h4": return (.heading, 4)
        case "h5": return (.heading, 5)
        case "h6": return (.heading, 6)
        case "li": return (.listItem, nil)
        case "blockquote": return (.blockquote, nil)
        case "pre": return (.preformatted, nil)
        case "figcaption": return (.caption, nil)
        default: return nil
        }
    }

    private struct OpenBlock {
        let tag: String
        let type: BlockType
        let level: Int?
        var marker: String = ""
        var listStyle: ListStyle?
    }

    private struct OpenList {
        let ordered: Bool
        var ordinal: Int
    }

    /// Converts a captured HTML fragment into blocks in document order.
    /// Relative image sources resolve against `baseURL`; `data:` images and
    /// sourceless `<img>`s are skipped, matching `__rlWalk`.
    nonisolated static func blocks(fromCapturedHTML html: String, baseURL: URL?) -> [ArticleBlock] {
        let cleaned = strippingNonContent(html)

        var blocks: [ArticleBlock] = []
        var stack: [OpenBlock] = []
        var lists: [OpenList] = []
        var buffer = ""

        func flush() {
            let raw = buffer
            buffer = ""
            let context = stack.last
            let type = context?.type ?? .paragraph
            let decoded = FeedParser.decodeEntities(raw)
            let text: String
            if type == .preformatted {
                // Verbatim: keep interior whitespace, drop only the outer blank
                // lines the source indentation contributes.
                text = decoded.trimmingCharacters(in: .newlines)
                    .replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            } else {
                text = decoded
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let quoted = stack.contains { $0.type == .blockquote } ? true : nil
            switch type {
            case .heading:
                blocks.append(ArticleBlock(
                    type: .heading, text: text, level: context?.level, isQuote: quoted
                ))
            case .listItem:
                // Marker baked into the text, exactly like `__rlWalk` does, so
                // the plain reader shows list structure and the block reader
                // skips its own composed marker.
                blocks.append(ArticleBlock(
                    type: .listItem,
                    text: (context?.marker ?? "\u{2022} ") + text,
                    listStyle: context?.listStyle,
                    markerBaked: true,
                    isQuote: quoted
                ))
            default:
                blocks.append(ArticleBlock(type: type, text: text, isQuote: quoted))
            }
        }

        var rest = Substring(cleaned)
        while let lt = rest.firstIndex(of: "<") {
            buffer += rest[rest.startIndex ..< lt]
            guard let gt = rest[lt...].firstIndex(of: ">") else {
                // Unterminated "<": literal text, not markup.
                buffer += rest[lt...]
                rest = rest[rest.endIndex...]
                break
            }
            let body = rest[rest.index(after: lt) ..< gt]
            rest = rest[rest.index(after: gt)...]

            let isClose = body.hasPrefix("/")
            let nameSource = isClose ? body.dropFirst() : body
            let name = String(nameSource.prefix { !$0.isWhitespace && $0 != "/" }).lowercased()
            guard !name.isEmpty else { continue }

            switch name {
            case "br":
                buffer += "\n"
            case "hr":
                if !isClose {
                    flush()
                    blocks.append(ArticleBlock(type: .divider))
                }
            case "img":
                if !isClose, let image = imageBlock(from: body, baseURL: baseURL) {
                    flush()
                    blocks.append(image)
                }
            case "ul", "ol":
                flush()
                if isClose {
                    if !lists.isEmpty { lists.removeLast() }
                } else {
                    lists.append(OpenList(
                        ordered: name == "ol",
                        ordinal: attribute("start", in: body).flatMap { Int($0) } ?? 1
                    ))
                }
            default:
                guard let kind = blockKind(name) else { continue }
                flush()
                if isClose {
                    if let index = stack.lastIndex(where: { $0.tag == name }) {
                        stack.removeSubrange(index...)
                    }
                } else {
                    var open = OpenBlock(tag: name, type: kind.type, level: kind.level)
                    if kind.type == .listItem {
                        let indent = String(
                            repeating: "\u{00a0}\u{00a0}", count: max(0, lists.count - 1)
                        )
                        if let list = lists.last, list.ordered {
                            open.marker = "\(indent)\(list.ordinal). "
                            open.listStyle = .ordered
                            lists[lists.count - 1].ordinal += 1
                        } else {
                            open.marker = "\(indent)\u{2022} "
                            open.listStyle = lists.isEmpty ? nil : .unordered
                        }
                    }
                    stack.append(open)
                }
            }
        }
        buffer += rest
        flush()

        return ArticleParser.coalescePreformatted(blocks)
    }

    /// Drops `<script>`/`<style>` bodies and comments. Reddit wraps every body
    /// in `<!-- SC_OFF -->` / `<!-- SC_ON -->` markers, which would otherwise
    /// land in the text.
    nonisolated static func strippingNonContent(_ html: String) -> String {
        var s = html
        for pattern in [
            "<script\\b[^>]*>[\\s\\S]*?</script\\s*>",
            "<style\\b[^>]*>[\\s\\S]*?</style\\s*>",
            "<!--[\\s\\S]*?-->",
        ] {
            s = s.replacingOccurrences(
                of: pattern, with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        return s
    }

    /// An `<img>` tag body → image block, or nil when there is no usable src.
    private nonisolated static func imageBlock(
        from tagBody: Substring, baseURL: URL?
    ) -> ArticleBlock? {
        guard let raw = attribute("src", in: tagBody) ?? attribute("data-src", in: tagBody),
              !raw.isEmpty, !raw.hasPrefix("data:") else { return nil }
        let decoded = FeedParser.decodeEntities(raw)
        guard let resolved = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
              resolved.scheme == "http" || resolved.scheme == "https" else { return nil }
        let width = attribute("width", in: tagBody).flatMap { Int($0) }
        let height = attribute("height", in: tagBody).flatMap { Int($0) }
        // Tracking pixels, same rule as the JS walk.
        if let width, width <= 2 { return nil }
        if let height, height <= 2 { return nil }
        return ArticleBlock(
            type: .image,
            src: resolved,
            alt: attribute("alt", in: tagBody),
            width: width,
            height: height
        )
    }

    /// Reads a double-, single-, or unquoted attribute value out of a tag body.
    nonisolated static func attribute(_ name: String, in tagBody: Substring) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let text = String(tagBody)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for group in 1 ... 3 {
            if let r = Range(match.range(at: group), in: text) { return String(text[r]) }
        }
        return nil
    }

    // MARK: - Floor assembly

    /// Whether captured HTML is a body FRAGMENT rather than a whole captured
    /// page. This is what scopes the floor.
    ///
    /// The two producers of `prefetchedHTML` differ exactly here: the Reddit
    /// paths hand us a body fragment (`<div class="md">…`) that IS the article,
    /// while the Safari extension hands us `document.documentElement.outerHTML`
    /// — a full page, complete with the nav chrome the quality gate exists to
    /// reject. Flooring a whole page would persist that chrome as an article,
    /// so the floor applies to fragments only. Pure.
    nonisolated static func isBodyFragment(_ html: String) -> Bool {
        for marker in ["<html", "<body", "<!doctype", "<frameset"] {
            if html.range(of: marker, options: [.caseInsensitive]) != nil { return false }
        }
        return true
    }

    /// Builds a `Parsed` straight from captured HTML — the never-fail floor for
    /// content we already hold. Returns nil when the input is a whole captured
    /// page (see `isBodyFragment`) or yields no text at all — in both cases the
    /// caller's real error is the honest answer.
    ///
    /// `title` is deliberately empty: `Article.apply(_:updateTitle:)` only
    /// adopts a non-empty parsed title, so the item keeps the title the save
    /// carried (the Reddit post title) instead of being renamed by the floor.
    nonisolated static func floorParsed(
        capturedHTML html: String, url: URL
    ) -> ArticleParser.Parsed? {
        guard isBodyFragment(html) else { return nil }
        let all = blocks(fromCapturedHTML: html, baseURL: url)
        let trimmed = CruftFilter.trimmingTrailingBoilerplate(all)
        let blocks = trimmed.kept
        let plainText = ArticleBlocks.derivePlainText(blocks)
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let words = plainText.split(whereSeparator: { $0.isWhitespace }).count
        return ArticleParser.Parsed(
            title: "",
            author: nil,
            siteName: nil,
            plainText: plainText,
            extractedHTML: html,
            heroImageURL: nil,
            estimatedReadingMinutes: max(1, words / 220),
            blocks: blocks,
            removedBlocks: trimmed.removed,
            isPaywalledPartial: false
        )
    }
}
