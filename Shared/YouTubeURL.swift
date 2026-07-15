import Foundation

/// Pure, dependency-free helpers for recognizing YouTube video URLs and pulling
/// the 11-character video ID out of them. Kept in `Shared/` and free of any
/// WebView/network so both the ingest router and unit tests can use it directly.
///
/// Recognized shapes (with `www.`, `m.`, `music.` host variants, and any query
/// tracking params like `?si=…` stripped implicitly by ID extraction):
///   - `youtube.com/watch?v=<id>`
///   - `youtu.be/<id>`
///   - `youtube.com/shorts/<id>`
///   - `youtube.com/embed/<id>` and `/v/<id>` (bonus; same offset space)
enum YouTubeURL {

    /// Canonical watch URL host used when building links.
    static let canonicalHost = "www.youtube.com"

    /// True for youtube.com and its relevant subdomains, plus `youtu.be`.
    static func isYouTubeHost(_ host: String?) -> Bool {
        guard var host = host?.lowercased(), !host.isEmpty else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    /// Extracts the 11-char video ID from any recognized YouTube watch/short/
    /// embed URL, or nil when `url` is not a YouTube *video* URL. Channel,
    /// playlist, and homepage URLs return nil (they are not videos to parse).
    static func videoID(from url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            // First non-empty path segment is the id: youtu.be/<id>
            let first = url.pathComponents.first { $0 != "/" && !$0.isEmpty }
            return first.flatMap(sanitizedID)
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

        // watch?v=<id>
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
           let id = sanitizedID(v) {
            return id
        }
        // /shorts/<id>, /embed/<id>, /v/<id>, /live/<id>
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if segments.count >= 2 {
            let leading = segments[0].lowercased()
            if ["shorts", "embed", "v", "live"].contains(leading) {
                return sanitizedID(segments[1])
            }
        }
        return nil
    }

    /// True when `url` is a YouTube *video* URL that should route to the video
    /// parser instead of the article parser. Pure — this is the routing predicate.
    static func isVideoURL(_ url: URL?) -> Bool {
        videoID(from: url) != nil
    }

    /// Canonical `https://www.youtube.com/watch?v=<id>` URL for a video ID.
    static func watchURL(videoID id: String) -> URL? {
        URL(string: "https://\(canonicalHost)/watch?v=\(id)")
    }

    /// Short share URL `https://youtu.be/<id>`. Used by the "Watch on YouTube"
    /// affordance: it is a universal link the YouTube app intercepts when
    /// installed, and opens in Safari otherwise.
    static func shareURL(videoID id: String) -> URL? {
        URL(string: "https://youtu.be/\(id)")
    }

    /// Default hero/thumbnail URL for a video ID. Uses `hqdefault.jpg`, which is
    /// generated for *every* video, rather than `maxresdefault.jpg`, which 404s
    /// for many uploads — a broken hero is worse than a slightly smaller one.
    static func thumbnailURL(videoID id: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    /// Validates and returns an id consisting of exactly 11 URL-safe base64
    /// characters, or nil. Trims a trailing path/query fragment that slipped in.
    private static func sanitizedID(_ raw: String) -> String? {
        // Guard against a segment that carries an extra path piece.
        let candidate = raw.split(separator: "/").first.map(String.init) ?? raw
        guard candidate.count == 11 else { return nil }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return candidate.unicodeScalars.allSatisfy(allowed.contains) ? candidate : nil
    }
}
