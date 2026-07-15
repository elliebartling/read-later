import Foundation
@preconcurrency import WebKit

/// Turns a YouTube watch URL into the same `ArticleParser.Parsed` an article
/// produces, so the reader, highlighting, TTS, and image cache need no changes.
///
/// Three-tier strategy (docs/youtube-save-design.md + the transcript-yield
/// fast-follow):
///  1. **json3 scrape** — read `ytInitialPlayerResponse.captions…captionTracks`
///     and fetch the chosen track's `json3` transcript from inside the page's
///     own JS context. Cheapest when it works, but as of mid-2026 most tracks
///     carry an `exp=xpe` PoToken gate that answers an empty 200 even to an
///     in-page fetch (verified live), so this tier usually yields nothing.
///  2. **Show-transcript UI drive** — programmatically expand the description,
///     click YouTube's own "Show transcript" button, and harvest the rendered
///     segment elements from the DOM (with a scroll pump for virtualized
///     panels). This rides YouTube's own BotGuard-minted token, so it works
///     where tier 1 is gated. Verified live 3/3 (incl. a PoToken-gated video).
///  3. **Metadata card (never fails):** thumbnail hero image block + title
///     heading + channel byline + description body (trailing link-pile lines
///     trimmed). A transcript-less save is a **success**, not an error.
///
/// The transcript (or description) becomes plain `.paragraph` blocks — no new
/// block kind, no timestamps in v1.
///
/// Single-slot like `ArticleParser` (one WKWebView, one continuation); ingest
/// serializes parses so callers don't collide.
@MainActor
final class VideoArticleParser: NSObject {

    static let shared = VideoArticleParser()

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

        // Adaptive load: watch pages are huge (megabytes of JS) and a fixed
        // 30s ceiling timed out on real cellular. Mirror ArticleParser's pump
        // philosophy — keep waiting while the load is PROGRESSING, resolve
        // early the moment the player-response globals are usable, and only
        // fail at an honest hard ceiling when the load is genuinely dead.
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            self.watchdog = Task { [weak self] in
                await self?.monitorLoad(videoID: fallbackID)
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
        var cues = Self.cues(fromJSON3Text: scraped.transcriptJSON)

        // Tier 2: the json3 track exists but answered empty (the PoToken gate)
        // — drive YouTube's own Show-transcript UI and harvest the rendered
        // segments. Only attempted when captions exist at all ("gated"), so a
        // caption-less video doesn't pay the UI-drive budget.
        if cues.isEmpty, scraped.captionState == "gated" {
            let segments = await runTranscriptUIDrive()
            cues = Self.cues(fromSegmentInnerTexts: segments)
            if !cues.isEmpty {
                NSLog("VideoArticleParser: UI-drive transcript harvested %d cues for %@",
                      cues.count, url.absoluteString)
            }
        }

        if cues.isEmpty {
            NSLog("VideoArticleParser: no transcript for %@ (caption state: %@) — saving metadata card",
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

    // MARK: - Adaptive load monitor

    /// Polls the in-flight load once a second. Resolves the load EARLY when the
    /// current document is the target watch page with `ytInitialPlayerResponse`
    /// available and the DOM interactive — everything the scrape tiers need —
    /// without waiting for the full `didFinish` (which on cellular can trail by
    /// tens of seconds of thumbnails and player JS). While neither ready nor
    /// finished, the deadline policy (`ArticleParser.PumpDeadline`) allows
    /// waiting past the soft cap only while `estimatedProgress` keeps growing;
    /// a genuinely dead load still times out at the hard ceiling.
    private func monitorLoad(videoID: String) async {
        var deadline = ArticleParser.PumpDeadline(
            soft: .seconds(20), hard: .seconds(90), growthGrace: .seconds(12)
        )
        let start = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard loadContinuation != nil, !Task.isCancelled else { return }

            if let value = try? await webView.evaluateJavaScript(Self.readinessProbeJS),
               let dict = value as? [String: Any] {
                let ready = Self.loadIsReady(
                    documentURL: (dict["url"] as? String) ?? "",
                    readyState: (dict["ready"] as? String) ?? "",
                    hasPlayerResponse: (ArticleParser.intValue(dict["pr"]) ?? 0) != 0,
                    videoID: videoID
                )
                if ready {
                    finishLoad(.success(()))
                    return
                }
            }

            // Progress feeds on WebKit's own load estimate; scaled so the
            // deadline's minimum-growth threshold (50) equals a 0.5% advance.
            let progress = Int(webView.estimatedProgress * 10_000)
            let elapsed = ContinuousClock.now - start
            if !deadline.shouldContinue(elapsed: elapsed, progress: progress) {
                if let pending = loadContinuation {
                    loadContinuation = nil
                    webView.stopLoading()
                    pending.resume(throwing: ArticleParser.ParseError.timedOut)
                }
                return
            }
        }
    }

    /// Snapshot of the live document the readiness triage runs on.
    private static let readinessProbeJS = """
    ({ url: document.URL || "", ready: document.readyState || "", pr: window.ytInitialPlayerResponse ? 1 : 0 })
    """

    /// Whether an in-flight watch-page load is already usable. Requires the
    /// player response, a hydratable DOM (`interactive`/`complete`), and — the
    /// crucial guard — that the CURRENT document is the target video: during a
    /// navigation the probe still sees the previous document, whose stale
    /// player response must never be scraped as this video's. Pure.
    nonisolated static func loadIsReady(
        documentURL: String,
        readyState: String,
        hasPlayerResponse: Bool,
        videoID: String
    ) -> Bool {
        guard hasPlayerResponse else { return false }
        guard readyState == "interactive" || readyState == "complete" else { return false }
        guard !videoID.isEmpty else { return false }
        return documentURL.contains(videoID)
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

    // MARK: - Tier 2: Show-transcript UI drive

    /// Drives YouTube's own transcript panel and returns the raw `innerText` of
    /// every rendered segment element (first-seen document order, deduped in
    /// JS by full text). Returns [] on any failure — the caller falls through
    /// to the metadata card. Never throws.
    private func runTranscriptUIDrive() async -> [String] {
        guard let value = try? await webView.callAsyncJavaScript(
            Self.transcriptUIDriveJS,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ), let dict = value as? [String: Any] else { return [] }
        let state = (dict["state"] as? String) ?? "unknown"
        let segments = (dict["segments"] as? [String]) ?? []
        if segments.isEmpty {
            NSLog("VideoArticleParser: UI-drive produced no segments (state: %@)", state)
        }
        return segments
    }

    /// Function body for `callAsyncJavaScript`, page content world. Sequence
    /// verified live against the mid-2026 desktop layout:
    ///  1. expand the description (`tp-yt-paper-button#expand`) — the
    ///     "Show transcript" button lives inside the expanded description;
    ///  2. click the transcript button
    ///     (`ytd-video-description-transcript-section-renderer button`, with
    ///     aria-label/text fallbacks);
    ///  3. wait for segment elements — the CURRENT DOM generation is
    ///     `transcript-segment-view-model` inside the `PAmodern_transcript_view`
    ///     engagement panel; `ytd-transcript-segment-renderer` is kept as the
    ///     legacy fallback selector;
    ///  4. harvest raw segment innerText with a scroll pump so a virtualizing
    ///     panel still yields the full transcript (banked first-seen, like the
    ///     ArticleParser harvester). The panel DOM is often DOUBLED (two panel
    ///     copies); the full-text dedupe key collapses the copies while
    ///     distinct cues (same words, different timestamp line) survive.
    /// All waits are internally bounded (~35s worst case, ~8s typical).
    private static let transcriptUIDriveJS = """
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const out = { state: "no-expander", segments: [] };
    function q(sel) { return document.querySelector(sel); }
    for (let i = 0; i < 12; i++) {
        const ex = q('ytd-text-inline-expander tp-yt-paper-button#expand')
            || q('#description-inline-expander #expand')
            || q('tp-yt-paper-button#expand');
        if (ex) { try { ex.click(); } catch (e) {} out.state = "no-button"; break; }
        await sleep(500);
    }
    await sleep(600);
    let btn = null;
    for (let i = 0; i < 12 && !btn; i++) {
        btn = q('ytd-video-description-transcript-section-renderer button');
        if (!btn) {
            const cands = Array.from(document.querySelectorAll('button'));
            btn = cands.find(b => (b.getAttribute('aria-label') || '').toLowerCase().includes('transcript'))
                || cands.find(b => (b.textContent || '').toLowerCase().includes('show transcript'));
        }
        if (!btn) await sleep(500);
    }
    if (!btn) { return out; }
    try { btn.click(); } catch (e) { out.state = "click-failed"; return out; }
    out.state = "no-segments";
    const SEG = 'transcript-segment-view-model, ytd-transcript-segment-renderer';
    let appeared = false;
    for (let i = 0; i < 20; i++) {
        await sleep(500);
        if (q(SEG)) { appeared = true; break; }
    }
    if (!appeared) { return out; }
    const panel = q('ytd-engagement-panel-section-list-renderer[target-id="PAmodern_transcript_view"]')
        || q('ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-searchable-transcript"]');
    let scroller = panel;
    if (panel) {
        const nodes = panel.querySelectorAll('*');
        for (let i = 0; i < nodes.length; i++) {
            const el = nodes[i];
            if (el.scrollHeight > el.clientHeight + 50 && el.clientHeight > 100) { scroller = el; break; }
        }
    }
    const seen = {};
    function harvest() {
        let added = 0;
        document.querySelectorAll(SEG).forEach(s => {
            const t = (s.innerText || '').trim();
            if (t && !seen[t]) { seen[t] = 1; out.segments.push(t); added++; }
        });
        return added;
    }
    harvest();
    let stable = 0;
    for (let i = 0; i < 30 && stable < 3; i++) {
        if (scroller) { try { scroller.scrollTop = scroller.scrollHeight; } catch (e) {} }
        await sleep(400);
        stable = harvest() === 0 ? stable + 1 : 0;
    }
    out.state = out.segments.length ? "ok" : "no-segments";
    return out;
    """

    /// Parses raw transcript-segment `innerText`s into cue strings. A segment's
    /// innerText is "<timestamp>\\n[<a11y duration label>\\n]<cue text…>" (the
    /// duration line may be absent — its div can be empty). Timestamp and
    /// duration-label lines are dropped, remaining lines join into one cue, and
    /// segments are deduped by their FULL raw text — the panel DOM renders two
    /// copies of every segment, and the timestamp line inside the key keeps
    /// legitimately repeated cues (same words at different times) distinct.
    /// Pure and unit-testable from captured fixtures.
    nonisolated static func cues(fromSegmentInnerTexts raw: [String]) -> [String] {
        var seen = Set<String>()
        var cues: [String] = []
        for text in raw {
            guard seen.insert(text).inserted else { continue }
            let kept = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !isTimestampLine($0) && !isDurationLabelLine($0) }
            let cue = kept.joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !cue.isEmpty { cues.append(cue) }
        }
        return cues
    }

    /// "0:05", "12:14", "1:02:33" — the segment's aria-hidden timestamp line.
    nonisolated static func isTimestampLine(_ line: String) -> Bool {
        line.range(of: "^\\d{1,2}(:\\d{2}){1,2}$", options: .regularExpression) != nil
    }

    /// "5 seconds", "1 minute, 5 seconds", "1 hour, 2 minutes, 3 seconds" — the
    /// segment's accessibility duration label line.
    nonisolated static func isDurationLabelLine(_ line: String) -> Bool {
        let pattern = "^\\d+ (hour|hours|minute|minutes|second|seconds)(,? \\d+ (minute|minutes|second|seconds))*$"
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

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

    /// Assembles a `Parsed` from scraped pieces.
    ///
    /// Every video article opens with a **metadata card**: the thumbnail as an
    /// `.image` block, the title as a `.heading`, and a channel byline
    /// `.caption`. The card must be BLOCKS — `heroImageURL` is set too, but
    /// nothing in either reader renders that field, which is exactly why the
    /// wave-1 fallback save showed a bare description with no title/channel/
    /// thumbnail. Body follows: transcript paragraphs when cues exist,
    /// otherwise the description with trailing link-pile lines trimmed
    /// (`trimTrailingLinkCruft`; the dropped lines ride in `removedBlocks` for
    /// the same debug inspectability the cruft filter gets). Pure.
    nonisolated static func buildParsed(
        videoID: String,
        title: String,
        author: String?,
        description: String,
        cues: [String]
    ) -> ArticleParser.Parsed {
        let cleanAuthor = (author?.isEmpty == false) ? author : nil

        // Metadata card — present on transcript saves too, so a video article
        // always opens with its identity even when the nav chrome is hidden.
        var blocks: [ArticleBlock] = []
        if !videoID.isEmpty, let thumb = YouTubeURL.thumbnailURL(videoID: videoID) {
            // hqdefault is 480×360; the dimensions reserve layout height.
            blocks.append(ArticleBlock(type: .image, src: thumb, alt: title, width: 480, height: 360))
        }
        if !title.isEmpty {
            blocks.append(ArticleBlock(type: .heading, text: title, level: 1))
        }
        if let cleanAuthor {
            blocks.append(ArticleBlock(type: .caption, text: "\(cleanAuthor) · YouTube"))
        }

        var removed: [ArticleBlock] = []
        let transcript = coalesceCues(cues)
        if !transcript.isEmpty {
            blocks.append(contentsOf: transcript.map { ArticleBlock(type: .paragraph, text: $0) })
        } else {
            let trimmed = trimTrailingLinkCruft(descriptionParagraphs(description))
            removed = trimmed.removed.map { ArticleBlock(type: .paragraph, text: $0) }
            if trimmed.kept.isEmpty {
                blocks.append(ArticleBlock(type: .paragraph, text: "No transcript available for this video."))
            } else {
                blocks.append(contentsOf: trimmed.kept.map { ArticleBlock(type: .paragraph, text: $0) })
            }
        }

        let plainText = ArticleBlocks.derivePlainText(blocks)
        let words = plainText.split(whereSeparator: { $0.isWhitespace }).count
        return ArticleParser.Parsed(
            title: title,
            author: cleanAuthor,
            siteName: "YouTube",
            plainText: plainText,
            extractedHTML: "",
            heroImageURL: YouTubeURL.thumbnailURL(videoID: videoID),
            estimatedReadingMinutes: max(1, words / 220),
            blocks: blocks,
            removedBlocks: removed,
            isPaywalledPartial: false
        )
    }

    /// Drops the trailing run of link-pile lines from a description's
    /// paragraphs — the "SUBSCRIBE / Follow me / merch / #hashtags" footer that
    /// dominated the device save. Deliberately conservative, CruftFilter-style:
    /// only TRAILING lines fall, only clearly link-shaped ones
    /// (`isLinkCruftLine`), and if every line matches, the original is returned
    /// untouched (never trim an article to empty). Pure.
    nonisolated static func trimTrailingLinkCruft(_ paragraphs: [String]) -> (kept: [String], removed: [String]) {
        var cut = paragraphs.count
        while cut > 0, isLinkCruftLine(paragraphs[cut - 1]) { cut -= 1 }
        guard cut > 0 else { return (paragraphs, []) }
        return (Array(paragraphs[..<cut]), Array(paragraphs[cut...]))
    }

    /// A description line that is a link, a labeled link ("Follow me on X:
    /// https://…" — at most four words of prose around the URL), or a pure
    /// hashtag/@-handle pile. Prose sentences that merely CONTAIN a link
    /// survive. Pure — internal for tests.
    nonisolated static func isLinkCruftLine(_ line: String) -> Bool {
        let words = line.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let isURLWord: (Substring) -> Bool = { w in
            w.range(of: "^(https?://|www\\.)", options: [.regularExpression, .caseInsensitive]) != nil
        }
        let prose = words.filter { !$0.hasPrefix("#") && !$0.hasPrefix("@") && !isURLWord($0) }
        if words.contains(where: isURLWord) {
            return prose.count <= 4
        }
        // No URL: only a pure hashtag/handle pile is cruft.
        return prose.isEmpty
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

    /// Splits a YouTube description into paragraphs, one per line. Description
    /// newlines are literal (a prose paragraph is one long line; link piles are
    /// one link per line), so line-splitting both reads correctly AND keeps
    /// each footer link on its own line for `trimTrailingLinkCruft` — blank-
    /// line splitting used to fuse "SUBSCRIBE:…\nFollow…\n#tags" into a single
    /// too-prosey paragraph the trim couldn't classify. Empties dropped. Pure.
    nonisolated static func descriptionParagraphs(_ description: String) -> [String] {
        description
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
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

    /// A navigation failure that resolves the load as failed only when it is a
    /// *real* failure. A YouTube watch page routinely cancels its first
    /// provisional navigation and supersedes it with another (consent
    /// interstitial, `?app=desktop`, m↔www redirect); WebKit reports that as
    /// `NSURLErrorCancelled`. Treating a cancel as fatal aborted the parse
    /// before the real page's `didFinish`, dropping a reachable video into
    /// `.failed` ("couldn't parse www.youtube.com") instead of a metadata save.
    /// We ignore cancels and let the superseding navigation — or the watchdog
    /// timeout — resolve the load. Pure so the triage is unit-testable.
    nonisolated static func isFatalNavigationError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return false }
        return true
    }

    private func handleNavigationFailure(_ error: Error) {
        guard Self.isFatalNavigationError(error) else { return }
        finishLoad(.failure(ArticleParser.ParseError.loadFailed(error)))
    }
}

extension VideoArticleParser: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoad(.success(())) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.handleNavigationFailure(error) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.handleNavigationFailure(error) }
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
