import Foundation

/// Pulls a web link out of a plain-text share payload.
///
/// Many apps (Medium is the one that bit us) hand the Share Sheet a plain-text
/// item like `"Some Article Title https://medium.com/…"` instead of a typed
/// `public.url` attachment. A WebURL-only activation rule never matches those,
/// so the extension doesn't even appear. Once we also accept text shares, this
/// recovers the first HTTP(S) link from the text so the normal PendingSave path
/// can run. Text with no link yields `nil`, and the caller surfaces the
/// existing "couldn't find a link" error.
enum SharedTextURLExtractor {
    /// The first `http`/`https` URL found in `text`, or `nil` if there is none.
    ///
    /// Uses `NSDataDetector`'s link detector, which also recognises bare hosts
    /// like `medium.com` (returned with an `http` scheme). Non-web links
    /// (`mailto:`, `tel:`, …) are ignored — this app only saves web pages.
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard match.resultType == .link, let url = match.url else { continue }
            let scheme = url.scheme?.lowercased()
            if scheme == "http" || scheme == "https" {
                return url
            }
        }
        return nil
    }
}
