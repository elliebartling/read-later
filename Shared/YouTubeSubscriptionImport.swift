import Foundation

/// One YouTube channel the user could subscribe to during a one-time import.
///
/// Both import sources (the logged-in `feed/channels` DOM harvest and the Google
/// Takeout `subscriptions.csv`) normalize into this. `reference` is whatever the
/// wave-1 `YouTubeChannel.resolveFeedURL(from:)` resolver understands — a
/// `/channel/UC…` URL, a `/@handle` URL, or a bare `@handle` — so subscribing a
/// selected channel reuses the exact wave-1 feed-URL machinery. `channelID` is
/// filled only when the source hands us a `UC…` id without a network round-trip
/// (the common case), so dedupe and feed-URL building can skip resolution.
struct ImportableChannel: Identifiable, Equatable, Hashable {
    /// Display name (channel title). Falls back to the reference when a source
    /// row carries no title.
    let title: String
    /// A reference `YouTubeChannel.resolveFeedURL(from:)` accepts.
    let reference: String
    /// The `UC…` channel id when known without network; nil for handle-only rows.
    let channelID: String?

    /// Stable identity for `ForEach`/selection: the channel id when known, else
    /// the reference (which is unique per row after dedupe).
    var id: String { channelID ?? reference }

    init(title: String, reference: String, channelID: String? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? reference : trimmed
        self.reference = reference
        self.channelID = channelID
    }

    /// The channel's Atom feed URL when the `UC…` id is already known — no
    /// network. Handle-only channels (`channelID == nil`) return nil and must go
    /// through `YouTubeChannel.resolveFeedURL(from:)` at subscribe time.
    var directFeedURL: URL? {
        channelID.flatMap(YouTubeChannel.feedURL(channelID:))
    }
}

/// Pure, network-free normalization of the two subscription-import sources into
/// `[ImportableChannel]`. Kept in `Shared/` and free of WebKit/SwiftData so both
/// the import model and unit tests drive it directly against captured fixtures.
///
/// Everything account-derived here is *scraped* and therefore fragile by nature
/// (see docs/youtube-save-design.md — Wave 2). The design's honesty contract is
/// that this only ever powers a **one-time** import: if YouTube reshapes the
/// `feed/channels` markup the DOM harvest yields nothing and the UI points the
/// user at the stable Takeout CSV path — it never silently loses subscriptions.
enum YouTubeSubscriptionImport {

    // MARK: - Google Takeout subscriptions.csv

    /// Parses Takeout's `subscriptions.csv`. The documented, stable format is a
    /// header row followed by `Channel Id,Channel Url,Channel Title` rows, e.g.
    ///
    ///     Channel Id,Channel Url,Channel Title
    ///     UCYO_jab_esuFRV4b17AJtAw,http://www.youtube.com/channel/UCYO_…,3Blue1Brown
    ///
    /// Robust to: quoted fields containing commas/quotes (RFC-4180 doubling),
    /// CRLF or LF line endings, a leading BOM, blank lines, and a missing header
    /// (a first row that is already data). Column order is taken from the header
    /// when present so a future reordering still maps correctly; without a header
    /// it assumes the documented `id,url,title` order. Rows without a valid `UC…`
    /// id are skipped. Deduped by channel id, first occurrence winning.
    static func channels(fromCSV text: String) -> [ImportableChannel] {
        let rows = parseCSV(text)
        guard !rows.isEmpty else { return [] }

        // Locate columns from a header row if one is present; otherwise assume
        // the documented order.
        var idCol = 0, urlCol = 1, titleCol = 2
        var dataRows = rows[...]
        if let header = rows.first, isHeaderRow(header) {
            for (index, cell) in header.enumerated() {
                switch normalizedHeader(cell) {
                case "channelid": idCol = index
                case "channelurl": urlCol = index
                case "channeltitle": titleCol = index
                default: break
                }
            }
            dataRows = rows.dropFirst()
        }

        var result: [ImportableChannel] = []
        var seen = Set<String>()
        for row in dataRows {
            guard idCol < row.count else { continue }
            let rawID = row[idCol].trimmingCharacters(in: .whitespacesAndNewlines)
            guard YouTubeChannel.isValidChannelID(rawID), seen.insert(rawID).inserted else { continue }
            let title = titleCol < row.count ? row[titleCol] : ""
            let url = urlCol < row.count ? row[urlCol].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            // Prefer the row's own URL as the resolver reference, but a `UC…` id
            // needs no resolution anyway (directFeedURL builds it).
            let reference = url.isEmpty ? "https://www.youtube.com/channel/\(rawID)" : url
            result.append(ImportableChannel(title: title, reference: reference, channelID: rawID))
        }
        return result
    }

    // MARK: - Logged-in feed/channels DOM harvest

    /// Classifies the raw channel anchors scraped from the logged-in
    /// `youtube.com/feed/channels` page into importable channels. The harvester's
    /// in-page JS returns one dictionary per candidate link with `name` (visible
    /// channel title / aria-label) and `href` (the link target, absolute or
    /// site-relative). This function is the **pure seam**: it is fixture-tested
    /// against a captured anchor list so the fragile part (the DOM shape) is the
    /// only thing that can rot, and it rots into "zero channels" — never a crash.
    ///
    /// Recognizes `/channel/UC…` (id known, no resolution needed), `/@handle`,
    /// `/c/<name>`, and `/user/<name>` links; everything else (nav, playlists,
    /// video links, avatars pointing at `/watch`) is dropped. Deduped by channel
    /// id when known, else by normalized reference URL — first occurrence wins,
    /// so a channel linked twice (avatar + name) collapses to one row.
    static func channels(fromAnchors anchors: [[String: String]]) -> [ImportableChannel] {
        var result: [ImportableChannel] = []
        var indexByKey: [String: Int] = [:]
        for anchor in anchors {
            guard let href = anchor["href"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty,
                  let classified = classifyAnchor(href: href)
            else { continue }
            let key = classified.channelID ?? classified.reference.lowercased()
            let name = (anchor["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = indexByKey[key] {
                // A channel is often linked twice (avatar with no text + name).
                // Keep the first row but upgrade a reference-fallback title when a
                // later duplicate carries a real name, so the picker never shows a
                // URL where a channel name belongs.
                if result[existing].title == result[existing].reference, !name.isEmpty {
                    result[existing] = ImportableChannel(
                        title: name,
                        reference: classified.reference,
                        channelID: classified.channelID
                    )
                }
                continue
            }
            indexByKey[key] = result.count
            result.append(ImportableChannel(
                title: name,
                reference: classified.reference,
                channelID: classified.channelID
            ))
        }
        return result
    }

    // MARK: - Private

    /// Maps a single `feed/channels` anchor href to a `(reference, channelID?)`,
    /// or nil when it is not a channel link. `reference` is always an absolute
    /// `https://www.youtube.com/…` URL the wave-1 resolver accepts.
    private static func classifyAnchor(href: String) -> (reference: String, channelID: String?)? {
        // Absolutize a site-relative href.
        let absolute: String
        if href.contains("://") {
            absolute = href
        } else if href.hasPrefix("/") {
            absolute = "https://www.youtube.com\(href)"
        } else {
            absolute = "https://www.youtube.com/\(href)"
        }
        guard let url = URL(string: absolute), YouTubeURL.isYouTubeHost(url.host) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first else { return nil }

        // /channel/UC… → id known directly.
        if first.lowercased() == "channel", segments.count >= 2,
           YouTubeChannel.isValidChannelID(segments[1])
        {
            let id = segments[1]
            return ("https://www.youtube.com/channel/\(id)", id)
        }
        // /@handle → resolve later. Reference keeps only the handle segment (drops
        // trailing /videos, /featured the subs page sometimes links to).
        if first.hasPrefix("@"), first.count > 1 {
            return ("https://www.youtube.com/\(first)", nil)
        }
        // Legacy /c/<name> and /user/<name>.
        if ["c", "user"].contains(first.lowercased()), segments.count >= 2 {
            return ("https://www.youtube.com/\(first.lowercased())/\(segments[1])", nil)
        }
        return nil
    }

    /// True when the row looks like Takeout's header (contains the literal
    /// "Channel Id" column, case/space-insensitive) rather than data.
    private static func isHeaderRow(_ row: [String]) -> Bool {
        row.contains { normalizedHeader($0) == "channelid" }
    }

    private static func normalizedHeader(_ cell: String) -> String {
        cell.lowercased().filter { !$0.isWhitespace }
    }

    /// Minimal RFC-4180 CSV reader: fields split on commas, `"`-quoted fields may
    /// contain commas/newlines, and a doubled `""` inside a quoted field is a
    /// literal quote. Handles CRLF/LF/CR line endings and a leading UTF-8 BOM.
    /// Returns rows of fields; blank rows are dropped.
    ///
    /// Scans over **Unicode scalars**, not `Character`s: Swift merges a `\r\n`
    /// pair into a single grapheme-cluster `Character`, so a `Character`-level
    /// scan would never see the line break in a CRLF file (as real Takeout
    /// exports are) and would fold every row into one. Scalars keep `\r` and `\n`
    /// distinct.
    static func parseCSV(_ text: String) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        let quote: Unicode.Scalar = "\""
        let comma: Unicode.Scalar = ","
        let lf: Unicode.Scalar = "\n"
        let cr: Unicode.Scalar = "\r"

        var rows: [[String]] = []
        var field = String.UnicodeScalarView()
        var row: [String] = []
        var inQuotes = false
        var i = 0
        func endField() { row.append(String(field)); field = String.UnicodeScalarView() }
        func endRow() { endField(); rows.append(row); row = [] }

        while i < scalars.count {
            let scalar = scalars[i]
            if inQuotes {
                if scalar == quote {
                    if i + 1 < scalars.count, scalars[i + 1] == quote {
                        field.append(quote) // escaped quote
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
            } else {
                switch scalar {
                case quote:
                    inQuotes = true
                case comma:
                    endField()
                case lf:
                    endRow()
                case cr:
                    if i + 1 < scalars.count, scalars[i + 1] == lf { i += 1 } // CRLF
                    endRow()
                default:
                    field.append(scalar)
                }
            }
            i += 1
        }
        // Flush the final field/row if the file did not end with a newline.
        if !field.isEmpty || !row.isEmpty { endRow() }
        // Drop rows that are entirely empty (blank lines).
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}
