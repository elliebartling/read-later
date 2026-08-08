import Foundation

/// Pure classification of a URL as *direct media* rather than an article.
/// The vocabulary it returns, `MediaKind`, lives in `Shared/Models` because
/// `Article` persists it.
///
/// This exists because the extractor cannot fail gracefully on media. Mozilla
/// Readability wants a document; hand it a JPEG and there is no `<article>`, no
/// `<p>`, and — crucially — no text at all, so the render pump's settle
/// condition (`textLength > 0`) can never be satisfied and every attempt burns
/// its full soft cap before the quality gate rejects an empty result. A Reddit
/// image post therefore cost ~74 seconds and *still* ended on "Couldn't parse
/// this page" (issue #75). Routing on the URL, before any WebView exists, is
/// what turns that into an instant image.
///
/// Deliberately a small, closed set of rules — hosts that only ever serve one
/// asset, plus a file-extension test that holds for any host. Everything else
/// stays an article, because a false positive here would replace a real page
/// with a broken `<img>`.
enum MediaLink {

    /// Extensions that are always a still image (or an animated GIF, which we
    /// render as an image because `AsyncImage`/`ArticleImageCache` animate it).
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "heif", "bmp", "tif", "tiff",
    ]

    /// Extensions that are always a video file. We do not play these in-app;
    /// they get a poster frame and an open-externally affordance.
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm"]

    /// Reddit's single-asset CDN hosts. `i.` and `preview.`/`external-preview.`
    /// serve stills; `v.` serves DASH video (its bare URL has no extension,
    /// which is exactly why the host has to be recognised by name).
    static let redditImageHosts: Set<String> = [
        "i.redd.it", "preview.redd.it", "external-preview.redd.it",
    ]
    static let redditVideoHosts: Set<String> = ["v.redd.it"]

    /// Direct-file CDN hosts for other services. Only hosts that serve the
    /// *asset* — `imgur.com/a/xyz` is an album **page** and stays an article.
    static let directFileHosts: Set<String> = ["i.imgur.com", "i.postimg.cc"]

    /// The kind of media `url` points at, or nil when it is (or might be) a
    /// readable page. Pure.
    static func kind(for url: URL) -> MediaKind? {
        let host = normalizedHost(url)
        let ext = url.pathExtension.lowercased()

        if redditVideoHosts.contains(host) { return .video }
        if RedditFeed.isRedditHost(host), isGalleryPath(url) { return .gallery }
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        // Extension-less asset hosts: the host alone is the guarantee.
        if redditImageHosts.contains(host) { return .image }
        if directFileHosts.contains(host), !ext.isEmpty { return .image }
        return nil
    }

    /// True for `reddit.com/gallery/<id>` — the URL a gallery post's `[link]`
    /// anchor carries in the RSS feed.
    static func isGalleryPath(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.first?.lowercased() == "gallery" && parts.count >= 2
    }

    /// Lowercased host with a trailing root dot removed, matching
    /// `RedditFeed.isRedditHost`'s normalization.
    private static func normalizedHost(_ url: URL) -> String {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return "" }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }
}
