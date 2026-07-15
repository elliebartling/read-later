import Foundation

/// A syndication feed parsed from RSS 2.0, Atom, or RDF (RSS 1.0) XML.
struct ParsedFeed {
    var title: String = ""
    var siteURL: URL?
    var items: [ParsedFeedItem] = []
}

struct ParsedFeedItem: Identifiable {
    var title: String = ""
    var url: URL?
    var guid: String?
    var publishedAt: Date?
    var summary: String?
    var author: String?
    /// Raw (entity-decoded) content HTML from the richest content element
    /// (`content:encoded` / Atom `<content>` / `<description>`). Kept alongside
    /// the plain-text `summary` so Reddit link/self classification and self-post
    /// rendering have the full markup. nil when the item carried no content.
    var contentHTML: String?
    /// Entry thumbnail from the Media RSS `media:thumbnail` element (YouTube
    /// channel feeds carry one per video). nil for feeds without it.
    var thumbnailURL: URL?

    /// Stable identity for SwiftUI lists: guid falls back to URL at parse time.
    var id: String { guid ?? url?.absoluteString ?? title }
}

/// Dependency-free feed parser built on Foundation's XMLParser.
///
/// Supports the three formats that cover real-world feeds: RSS 2.0, Atom, and
/// RDF/RSS 1.0. Feeds in the wild are frequently sloppy, so parsing is lenient:
/// whatever items were extracted before a well-formedness error are kept.
enum FeedParser {
    enum ParseError: Error {
        /// The document's root element is not a known feed root.
        case notAFeed
        /// The document was malformed before any usable content appeared.
        case malformed
    }

    static func parse(data: Data) throws -> ParsedFeed {
        let delegate = FeedXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let wellFormed = parser.parse()

        guard delegate.sawFeedRoot else { throw ParseError.notAFeed }
        let feed = delegate.feed
        if !wellFormed, feed.items.isEmpty, feed.title.isEmpty {
            throw ParseError.malformed
        }
        return feed
    }

    // MARK: - Dates

    /// Parses the date formats found in feeds: RFC 822 (RSS pubDate) and
    /// ISO 8601 (Atom published/updated, dc:date).
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for formatter in rfc822Formatters {
            if let date = formatter.date(from: s) { return date }
        }
        for formatter in iso8601Formatters {
            if let date = formatter.date(from: s) { return date }
        }
        return dateOnlyFormatter.date(from: s)
    }

    // DateFormatter is documented thread-safe on iOS 7+; shared instances are fine.
    private static let rfc822Formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy HH:mm:ss zzz",
    ].map(makeFormatter)

    private static let dateOnlyFormatter = makeFormatter("yyyy-MM-dd")

    private static let iso8601Formatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    // MARK: - Summary cleanup

    /// Feed descriptions are HTML more often than not. Reduce to short plain
    /// text suitable for a list row: strip tags, decode entities, collapse
    /// whitespace, cap the length.
    static func plainSummary(_ html: String) -> String? {
        var text = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        text = decodeEntities(text)
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }

    /// Decodes the named entities that actually show up in feed summaries plus
    /// numeric character references. Not a general HTML entity table.
    static func decodeEntities(_ input: String) -> String {
        var s = input
        // Numeric references first: &#8217; and &#x2019;
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: s),
                      let numRange = Range(match.range(at: 1), in: s) else { continue }
                let num = s[numRange]
                let scalarValue: UInt32?
                if num.hasPrefix("x") || num.hasPrefix("X") {
                    scalarValue = UInt32(num.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(num)
                }
                if let value = scalarValue, let scalar = Unicode.Scalar(value) {
                    s.replaceSubrange(full, with: String(Character(scalar)))
                }
            }
        }
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&amp;", "&"), // must be last so it doesn't create new entities
        ]
        for (entity, replacement) in named {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        return s
    }
}

// MARK: - XMLParser delegate

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    var feed = ParsedFeed()
    private(set) var sawFeedRoot = false

    private var stack: [String] = []
    private var text = ""
    private var item: ParsedFeedItem?
    /// Width of the currently-chosen `media:thumbnail`, so the widest wins when
    /// an entry offers several. Reset at each entry boundary.
    private var lastThumbnailWidth: Int?

    private static let feedRoots: Set<String> = ["rss", "feed", "rdf:rdf"]
    private static let channelLevels: Set<String> = ["channel", "feed"]

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if stack.isEmpty {
            sawFeedRoot = Self.feedRoots.contains(name)
        }
        stack.append(name)
        text = ""

        switch name {
        case "item", "entry":
            item = ParsedFeedItem()
            lastThumbnailWidth = nil
        case "media:thumbnail":
            // Media RSS thumbnail (YouTube channel feeds): attributes only.
            // Keep the widest when several are offered.
            if item != nil, let urlString = attributes["url"], let url = URL(string: urlString) {
                let width = attributes["width"].flatMap { Int($0) } ?? 0
                if item?.thumbnailURL == nil || width >= (lastThumbnailWidth ?? 0) {
                    item?.thumbnailURL = url
                    lastThumbnailWidth = width
                }
            }
        case "link":
            // Atom-style link: everything lives in attributes. RSS <link> has
            // text content instead and is handled in didEndElement.
            if let href = attributes["href"] {
                let rel = attributes["rel"] ?? "alternate"
                guard rel == "alternate" else { return }
                if item != nil {
                    if item?.url == nil { item?.url = URL(string: href) }
                } else if feed.siteURL == nil {
                    feed.siteURL = URL(string: href)
                }
            }
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let name = elementName.lowercased()
        if !stack.isEmpty { stack.removeLast() }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        if var current = item {
            switch name {
            case "item", "entry":
                if current.guid == nil { current.guid = current.url?.absoluteString }
                feed.items.append(current)
                item = nil
                return
            case "title":
                if current.title.isEmpty {
                    current.title = FeedParser.decodeEntities(value)
                }
            case "link":
                if current.url == nil, let url = URL(string: value) { current.url = url }
            case "guid", "id":
                if !value.isEmpty { current.guid = value }
            case "pubdate", "published", "dc:date":
                if let date = FeedParser.parseDate(value) { current.publishedAt = date }
            case "updated":
                // Only a fallback: a true publication date always wins,
                // regardless of element order within the entry.
                if current.publishedAt == nil { current.publishedAt = FeedParser.parseDate(value) }
            case "description", "summary", "content:encoded", "content":
                if current.summary == nil { current.summary = FeedParser.plainSummary(value) }
                // Keep the raw markup too. Prefer the rich content elements
                // (`content:encoded` / Atom `<content>`) over `description` /
                // `summary`, which are often just an excerpt.
                if !value.isEmpty {
                    if name == "content:encoded" || name == "content" {
                        current.contentHTML = value
                    } else if current.contentHTML == nil {
                        current.contentHTML = value
                    }
                }
            case "dc:creator":
                if !value.isEmpty { current.author = value }
            case "name":
                // Atom <entry><author><name>…</name></author>
                if stack.last == "author", current.author == nil, !value.isEmpty {
                    current.author = value
                }
            case "author":
                // RSS-style plain author text. Empty for Atom's container form.
                if current.author == nil, !value.isEmpty { current.author = value }
            default:
                break
            }
            item = current
            return
        }

        switch name {
        case "title":
            // Guard on the parent so <image><title> can't clobber the channel title.
            if feed.title.isEmpty, let parent = stack.last, Self.channelLevels.contains(parent) {
                feed.title = FeedParser.decodeEntities(value)
            }
        case "link":
            if feed.siteURL == nil, stack.last == "channel", let url = URL(string: value) {
                feed.siteURL = url
            }
        default:
            break
        }
    }
}
