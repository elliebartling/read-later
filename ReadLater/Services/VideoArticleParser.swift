import Foundation
@preconcurrency import WebKit

/// Turns a YouTube watch URL into the same `ArticleParser.Parsed` an article
/// produces, so the reader, highlighting, TTS, and image cache need no changes.
///
/// Strategy (see docs/youtube-save-design.md):
///  - **Primary:** load the watch page in an off-screen WKWebView with a desktop
///    Safari UA, read `ytInitialPlayerResponse` for metadata + `captionTracks`,
///    and fetch the chosen track's `json3` transcript *from inside the page's
///    own JS context* (so YouTube's session/PoToken is inherited). The cues are
///    coalesced into readable `.paragraph` blocks — no new block kind, no
///    timestamps in v1.
///  - **Fallback (never fails):** a metadata-only save — title, channel
///    (`author`), thumbnail hero (`heroImageURL`), description as body. A
///    transcript-less save is a **success**, not an error.
///
/// Single-slot like `ArticleParser` (one WKWebView, one continuation); ingest
/// serializes parses so callers don't collide.
@MainActor
final class VideoArticleParser: NSObject {

    static let shared = VideoArticleParser()

    private let loadTimeout: Duration = .seconds(30)

    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        // Share the persistent cookie jar with the in-app site-login sheet, so a
        // YouTube session the user established (Site Logins) is present here and
        // the caption fetch inherits it.
        config.websiteDataStore = SiteLoginStore.shared.dataStore
        config.suppressesIncrementalRendering = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 2000), configuration: config)
        // Desktop Safari UA: the mobile UA gets `m.youtube.com`, which lacks the
        // transcript surface. Matches a current macOS Safari token.
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        return wv
    }()

    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var watchdog: Task<Void, Never>?
    private var isParsing = false

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    /// Parses `url` (a YouTube watch/short/embed URL) into a `Parsed`. Throws
    /// only when the page cannot be loaded at all (network failure/timeout) —
    /// a page that loads but has no transcript still returns a metadata `Parsed`.
    func parse(url: URL) async throws -> ArticleParser.Parsed {
        guard !isParsing else { throw ArticleParser.ParseError.busy }
        isParsing = true
        defer { isParsing = false }

        let fallbackID = YouTubeURL.videoID(from: url) ?? ""

        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            self.watchdog = Task { [weak self] in
                try? await Task.sleep(for: self?.loadTimeout ?? .seconds(30))
                guard let self, !Task.isCancelled else { return }
                if let pending = self.loadContinuation {
                    self.loadContinuation = nil
                    self.webView.stopLoading()
                    pending.resume(throwing: ArticleParser.ParseError.timedOut)
                }
            }
        }
        watchdog?.cancel()
        watchdog = nil

        // Let the player-response globals and session cookie settle before the
        // in-page caption fetch.
        try? await Task.sleep(for: .milliseconds(700))

        let scraped: Scraped
        do {
            scraped = try await runScrape()
        } catch {
            NSLog("VideoArticleParser: scrape JS failed for %@: %@", url.absoluteString, String(describing: error))
            // Page loaded but the scrape threw (consent wall, layout change):
            // still produce a minimal metadata save rather than failing.
            return Self.buildParsed(videoID: fallbackID, title: "YouTube video", author: nil, description: "", cues: [])
        }

        let videoID = scraped.videoID.isEmpty ? fallbackID : scraped.videoID
        let cues = Self.cues(fromJSON3Text: scraped.transcriptJSON)
        if cues.isEmpty {
            NSLog("VideoArticleParser: no transcript for %@ (caption state: %@) — saving metadata only",
                  url.absoluteString, scraped.captionState)
        }
        return Self.buildParsed(
            videoID: videoID,
            title: scraped.title,
            author: scraped.author,
            description: scraped.description,
            cues: cues
        )
    }

    // MARK: - In-page scrape

    /// What the in-page JS returns. `transcriptJSON` is the raw `json3` body of
    /// the first caption track that returned content (empty when gated/absent);
    /// the cue parsing itself is done in pure Swift (`cues(fromJSON3Text:)`) so
    /// it is unit-testable from a captured sample.
    private struct Scraped {
        var videoID: String
        var title: String
        var author: String
        var description: String
        var transcriptJSON: String
        var captionState: String
    }

    private func runScrape() async throws -> Scraped {
        let value = try await webView.callAsyncJavaScript(
            Self.scrapeJS,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let dict = value as? [String: Any] else {
            throw ArticleParser.ParseError.readabilityFailed("non-dictionary video scrape result")
        }
        return Scraped(
            videoID: (dict["videoId"] as? String) ?? "",
            title: (dict["title"] as? String) ?? "",
            author: (dict["author"] as? String) ?? "",
            description: (dict["description"] as? String) ?? "",
            transcriptJSON: (dict["transcriptJSON"] as? String) ?? "",
            captionState: (dict["captionState"] as? String) ?? "none"
        )
    }

    /// Function body for `callAsyncJavaScript`. Runs in the page content world so
    /// `window.ytInitialPlayerResponse` is visible and `fetch` inherits the
    /// page's origin/session (the only place the caption PoToken exists). Picks a
    /// caption track (manual English → auto English → any manual → first) and
    /// returns the raw `json3` body of the first one that answers non-empty.
    private static let scrapeJS = """
    const pr = window.ytInitialPlayerResponse || null;
    const vd = (pr && pr.videoDetails) || {};
    const out = {
        videoId: vd.videoId || "",
        title: vd.title || (document.title || "").replace(/ - YouTube$/, ""),
        author: vd.author || "",
        description: vd.shortDescription || "",
        transcriptJSON: "",
        captionState: "none"
    };
    try {
        const list = pr && pr.captions && pr.captions.playerCaptionsTracklistRenderer;
        const tracks = (list && list.captionTracks) || [];
        if (tracks.length) {
            out.captionState = "gated";
            const en = tracks.filter(t => String(t.languageCode || "").toLowerCase().indexOf("en") === 0);
            const cand = [];
            en.forEach(t => { if (t.kind !== "asr") cand.push(t); });
            en.forEach(t => { if (t.kind === "asr") cand.push(t); });
            tracks.forEach(t => { if (t.kind !== "asr") cand.push(t); });
            if (tracks[0]) cand.push(tracks[0]);
            const seen = {};
            for (let i = 0; i < cand.length; i++) {
                const t = cand[i];
                if (!t || !t.baseUrl || seen[t.baseUrl]) continue;
                seen[t.baseUrl] = 1;
                try {
                    const resp = await fetch(t.baseUrl + "&fmt=json3");
                    if (!resp.ok) continue;
                    const txt = await resp.text();
                    if (txt && txt.indexOf("events") !== -1) {
                        out.transcriptJSON = txt;
                        out.captionState = "ok";
                        break;
                    }
                } catch (e) {}
            }
        }
    } catch (e) { out.captionError = String(e); }
    return out;
    """

    /// Parses a `json3` caption body into an ordered array of cue strings. Each
    /// event's `segs[].utf8` are concatenated and whitespace-collapsed; events
    /// without `segs` (formatting-only) are skipped. Pure and unit-testable.
    nonisolated static func cues(fromJSON3Text text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let events = object["events"] as? [[String: Any]]
        else { return [] }
        var cues: [String] = []
        for event in events {
            guard let segs = event["segs"] as? [[String: Any]] else { continue }
            let joined = segs.compactMap { $0["utf8"] as? String }.joined()
            let cleaned = joined
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty { cues.append(cleaned) }
        }
        return cues
    }

    // MARK: - Pure assembly (unit-testable without a WebView)

    /// Assembles a `Parsed` from scraped pieces. When cues are present they
    /// become the body (coalesced into readable paragraphs); otherwise the
    /// description is the body (the metadata-only fallback). Pure.
    nonisolated static func buildParsed(
        videoID: String,
        title: String,
        author: String?,
        description: String,
        cues: [String]
    ) -> ArticleParser.Parsed {
        let transcript = coalesceCues(cues)
        let bodyParagraphs: [String]
        if !transcript.isEmpty {
            bodyParagraphs = transcript
        } else {
            let desc = descriptionParagraphs(description)
            bodyParagraphs = desc.isEmpty ? ["No transcript available for this video."] : desc
        }
        let blocks = bodyParagraphs.map { ArticleBlock(type: .paragraph, text: $0) }
        let plainText = ArticleBlocks.derivePlainText(blocks)
        let words = plainText.split(whereSeparator: { $0.isWhitespace }).count
        let cleanAuthor = (author?.isEmpty == false) ? author : nil
        return ArticleParser.Parsed(
            title: title,
            author: cleanAuthor,
            siteName: "YouTube",
            plainText: plainText,
            extractedHTML: "",
            heroImageURL: YouTubeURL.thumbnailURL(videoID: videoID),
            estimatedReadingMinutes: max(1, words / 220),
            blocks: blocks,
            removedBlocks: [],
            isPaywalledPartial: false
        )
    }

    /// Coalesces short caption cues into readable paragraphs of roughly
    /// `maxWords` words, breaking a little early on sentence-final punctuation
    /// when one is available. Auto-captions carry no punctuation, so the word
    /// cap does most of the work. Pure and order-preserving.
    nonisolated static func coalesceCues(_ cues: [String], maxWords: Int = 55) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        var wordCount = 0
        for cue in cues {
            let words = cue.split(whereSeparator: { $0.isWhitespace }).count
            current.append(cue)
            wordCount += words
            let endsSentence = cue.hasSuffix(".") || cue.hasSuffix("?") || cue.hasSuffix("!")
            if wordCount >= maxWords || (endsSentence && wordCount >= maxWords * 2 / 3) {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll()
                wordCount = 0
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs
    }

    /// Splits a YouTube description into paragraphs: on blank lines when present,
    /// else on single newlines. Empty parts are dropped. Pure.
    nonisolated static func descriptionParagraphs(_ description: String) -> [String] {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var parts = trimmed.components(separatedBy: "\n\n")
        if parts.count == 1 {
            parts = trimmed.components(separatedBy: "\n")
        }
        return parts
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func finishLoad(_ result: Result<Void, Error>) {
        watchdog?.cancel()
        watchdog = nil
        guard let cont = loadContinuation else { return }
        loadContinuation = nil
        switch result {
        case .success: cont.resume()
        case .failure(let error): cont.resume(throwing: error)
        }
    }
}

extension VideoArticleParser: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoad(.success(())) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad(.failure(ArticleParser.ParseError.loadFailed(error))) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad(.failure(ArticleParser.ParseError.loadFailed(error))) }
    }
}

// MARK: - Routing

/// Single parse entry point used by both ingest and the reader's re-extract, so
/// the YouTube-vs-article routing decision lives in exactly one place. The
/// decision itself is the pure `YouTubeURL.isVideoURL` predicate.
@MainActor
enum ArticleParsing {
    static func parse(url: URL, prefetchedHTML: String? = nil) async throws -> ArticleParser.Parsed {
        if YouTubeURL.isVideoURL(url) {
            return try await VideoArticleParser.shared.parse(url: url)
        }
        return try await ArticleParser.shared.parse(url: url, prefetchedHTML: prefetchedHTML)
    }
}

extension Article {
    /// Whether this article is a saved YouTube video, derived purely from its
    /// URL. Derivation (not a stored flag) keeps it CloudKit-free and always
    /// correct — the badge and watch affordance need no schema change. Covers
    /// watch, `youtu.be`, shorts, and embed URLs.
    var isVideoArticle: Bool {
        YouTubeURL.isVideoURL(url)
    }
}
