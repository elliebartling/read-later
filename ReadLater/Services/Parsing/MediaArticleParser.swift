import Foundation

/// Builds a reader article for a **media post** — a save whose content is a
/// picture, a video, or a gallery rather than prose — entirely in Swift, with
/// no WKWebView and no Readability.
///
/// Why it exists (issue #75). A Reddit image post is structurally a *link*
/// post: its RSS entry carries a `[link]` anchor pointing at
/// `https://i.redd.it/abc.jpeg`, distinct from `[comments]`. The wave-1
/// link/self split therefore saved the JPEG's URL and handed it to the article
/// extractor, which cannot succeed on an image — and, on the way, threw away
/// the entry's own content, where the post's preview image and self-text were
/// sitting. Ellen's build-44 screenshot ("Reddit parsing doesn't work at all")
/// is that path: nine seconds of spinner, then "Couldn't parse this page".
///
/// Two entry shapes reach here, and both resolve to the same `Attachment`:
///
/// - **A direct media URL** (`i.redd.it/…`, `v.redd.it/…`, any `*.png`),
///   whatever the source — a feed open, the share sheet, the Safari
///   extension, the Reddit saved-posts import, or a re-parse of an article
///   that had already landed `.failed`. That last one is what heals the
///   articles Ellen's build already spoiled.
/// - **A captured Reddit entry body** whose `[link]` target is media. Here the
///   post's own text rides along in the same fragment, so an image post with a
///   caption renders as image + caption instead of image alone.
///
/// Everything is pure and `nonisolated`: no WebView, no network, no actor. The
/// image bytes are fetched later, by `ImageBlockView`, exactly like any other
/// article image.
///
/// **No new `BlockType`.** The lead media is an ordinary `.image` block, which
/// every reader (and every already-shipped decoder) understands. A new enum
/// case would be a cross-version hazard — an older device decoding an unknown
/// `type` string drops the block entirely — so the media *identity* travels as
/// additive optional fields (`Parsed.mediaURL` / `mediaKind`) beside the
/// blocks, never inside them.
enum MediaArticleParser {

    /// The media a save resolves to, plus the still we can show for it.
    struct Attachment: Equatable {
        let kind: MediaKind
        /// The asset itself: the full-resolution image, the video, or the
        /// gallery permalink. Persisted to `Article.mediaURL`.
        let url: URL
        /// A still we can render right now. For an image post this is usually
        /// nil (the asset *is* the still); for video and gallery it is the
        /// feed's preview frame, and it is all we have.
        let posterURL: URL?
    }

    // MARK: - Resolution

    /// Resolves what this save actually points at, or nil when it is an
    /// ordinary page. Pure.
    nonisolated static func attachment(url: URL, capturedHTML: String?) -> Attachment? {
        let fragment = bodyFragment(capturedHTML)
        let poster = posterURL(inFragment: fragment, baseURL: url)

        // The saved URL is itself media (direct save, or an article being
        // re-parsed after the old link-post routing saved the asset URL).
        if let kind = MediaLink.kind(for: url) {
            // A poster only helps when it isn't the asset we're already showing.
            return Attachment(kind: kind, url: url, posterURL: poster == url ? nil : poster)
        }

        // Otherwise: a captured Reddit entry whose `[link]` is media.
        guard let fragment,
              let target = RedditFeed.externalURL(fromContentHTML: fragment),
              let kind = MediaLink.kind(for: target)
        else { return nil }
        return Attachment(kind: kind, url: target, posterURL: poster == target ? nil : poster)
    }

    /// Renders a media post, or nil when there is nothing renderable — in
    /// which case the caller falls through to the ordinary extractor and, if
    /// that also fails, reports an honest error.
    ///
    /// Nil happens for a bare `v.redd.it/<id>` saved with no feed entry behind
    /// it: no poster frame exists anywhere in the save, and an article
    /// consisting of one unplayable link is worse than the failure state.
    nonisolated static func parsed(url: URL, capturedHTML: String?) -> ArticleParser.Parsed? {
        guard let attachment = attachment(url: url, capturedHTML: capturedHTML) else { return nil }
        let fragment = bodyFragment(capturedHTML)

        // The post's own words, if it had any. The feed's preview `<img>` is
        // dropped: we render the full-resolution asset (or the poster) as the
        // lead block, and a second, smaller copy of the same picture directly
        // underneath reads as a bug.
        let captured = fragment.map {
            CapturedHTMLBlocks.blocks(fromCapturedHTML: $0, baseURL: url)
        } ?? []
        let body = strippingSyndicationFooter(captured.filter { $0.type != .image })

        var blocks: [ArticleBlock] = []
        if let lead = leadBlock(for: attachment) { blocks.append(lead) }
        blocks.append(contentsOf: body.kept)
        guard !blocks.isEmpty else { return nil }

        let plainText = ArticleBlocks.derivePlainText(blocks)
        let words = plainText.split(whereSeparator: { $0.isWhitespace }).count
        return ArticleParser.Parsed(
            // Empty on purpose: `Article.apply(_:updateTitle:)` only adopts a
            // non-empty parsed title, so the post keeps the title the save
            // carried — the Reddit post title, which is the caption a picture
            // post is actually about.
            title: "",
            author: nil,
            siteName: nil,
            plainText: plainText,
            extractedHTML: fragment ?? "",
            // Gives the library row (and the share card) a real thumbnail
            // instead of the grey placeholder a media post used to get.
            heroImageURL: blocks.first(where: { $0.type == .image })?.src,
            // A picture is not a two-minute read. Zero suppresses the reading
            // estimate entirely, which is honest for an image-only post; a post
            // with a caption gets the normal estimate.
            estimatedReadingMinutes: words == 0 ? 0 : max(1, words / 220),
            blocks: blocks,
            removedBlocks: body.removed,
            isPaywalledPartial: false,
            mediaURL: attachment.url,
            mediaKind: attachment.kind
        )
    }

    // MARK: - Pieces

    /// The lead block: the asset itself for an image, the poster frame for a
    /// video or gallery (both of which we cannot render inline). Nil when a
    /// video/gallery save carries no poster.
    nonisolated static func leadBlock(for attachment: Attachment) -> ArticleBlock? {
        switch attachment.kind {
        case .image:
            return ArticleBlock(type: .image, src: attachment.url)
        case .video, .gallery:
            // Note the deliberate limit (documented in
            // docs/reddit-media-posts.md): the RSS surface exposes exactly one
            // still per post. A gallery's remaining images and a video's
            // playable stream both need the Reddit JSON/OAuth API, so v1 shows
            // the cover/poster and links out.
            return attachment.posterURL.map { ArticleBlock(type: .image, src: $0) }
        }
    }

    /// First image source in the captured fragment — Reddit's `preview.redd.it`
    /// (image/gallery) or `external-preview.redd.it` (video) still.
    nonisolated static func posterURL(inFragment fragment: String?, baseURL: URL) -> URL? {
        guard let fragment else { return nil }
        return CapturedHTMLBlocks
            .blocks(fromCapturedHTML: fragment, baseURL: baseURL)
            .first { $0.type == .image }?
            .src
    }

    /// Captured HTML, but only when it is a body fragment. A whole captured
    /// page (the Safari extension's `documentElement.outerHTML`) is never
    /// treated as a media post's body — same scoping rule as
    /// `CapturedHTMLBlocks.floorParsed`, and for the same reason: its nav
    /// chrome is not article text.
    nonisolated static func bodyFragment(_ html: String?) -> String? {
        guard let html, CapturedHTMLBlocks.isBodyFragment(html) else { return nil }
        return html
    }

    /// Drops the trailing "submitted by /u/name [link] [comments]" run and
    /// strips a footer glued to the end of the last surviving block.
    ///
    /// Deliberately *not* `CruftFilter.trimmingTrailingBoilerplate`: that one
    /// refuses to empty an article, because for a self post the footer is
    /// better than nothing. Here the picture is the content, so a body of
    /// nothing but the footer must come out completely — otherwise every image
    /// post renders "submitted by /u/somebody" as its caption.
    nonisolated static func strippingSyndicationFooter(
        _ blocks: [ArticleBlock]
    ) -> (kept: [ArticleBlock], removed: [ArticleBlock]) {
        var cut = blocks.count
        while cut > 0, CruftFilter.isTrailingBoilerplate(blocks[cut - 1]) { cut -= 1 }
        var kept = Array(blocks[..<cut])
        let removed = Array(blocks[cut...])
        if let last = kept.indices.last(where: { kept[$0].type.isTextBearing }),
           let text = kept[last].text {
            let stripped = CruftFilter.strippingTrailingBoilerplate(text)
            if stripped != text, !stripped.isEmpty {
                var block = kept[last]
                block.text = stripped
                kept[last] = block
            }
        }
        return (kept, removed)
    }
}
