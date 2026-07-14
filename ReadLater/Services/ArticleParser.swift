import Foundation
@preconcurrency import WebKit

/// Extracts a readable article body from an arbitrary web URL by loading the
/// page in an off-screen WKWebView and running Mozilla's Readability.js on it.
///
/// Bundle `ReadLater/Resources/readability.js` (see README) before use. If the
/// bundled file is missing we fall back to a minimal <meta>/<title>-based
/// extractor so the pipeline still produces *something*.
///
/// Single-slot: one parse at a time (one WKWebView, one continuation).
/// Callers must serialize — PendingSaveIngest does — or handle `.busy`.
/// A watchdog aborts loads after `loadTimeout` so one hung page can't stall
/// every future save.
@MainActor
final class ArticleParser: NSObject {

    struct Parsed {
        let title: String
        let author: String?
        let siteName: String?
        let plainText: String
        let extractedHTML: String
        let heroImageURL: URL?
        let estimatedReadingMinutes: Int
        /// Typed reader blocks in document order. Empty on the fallback path or
        /// when the JS walk emitted nothing usable.
        let blocks: [ArticleBlock]
        /// Blocks the cruft filter removed (docs/parser-cruft-design.md), in
        /// document order. Persisted on Article for debugging so a wrong
        /// removal is inspectable; empty when nothing was filtered.
        let removedBlocks: [ArticleBlock]
        /// True when the page is metered/member-only and only the free preview
        /// reached the WebView (see `PaywallDetector`). The captured text is
        /// therefore partial. Additive to the quality gate — a preview is real
        /// prose and may pass — so it never blocks saving; it just flags it.
        let isPaywalledPartial: Bool
    }

    static let shared = ArticleParser()

    private let loadTimeout: Duration = .seconds(25)

    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        // Tall phone-width frame: lazy-rendering sites (Medium) mount content
        // through viewport-rooted IntersectionObservers, and a zero-size frame
        // gives them a zero-size viewport — nothing below the fold ever renders.
        // A tall viewport makes most of the article "visible" at once; the
        // scroll pump in `pumpFullRender` covers whatever still isn't.
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 4000), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ReadLater/0.1"
        return wv
    }()

    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var watchdog: Task<Void, Never>?
    private var isParsing = false

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func parse(url: URL, prefetchedHTML: String? = nil) async throws -> Parsed {
        guard !isParsing else { throw ParseError.busy }
        isParsing = true
        defer { isParsing = false }

        if let html = prefetchedHTML {
            webView.loadHTMLString(html, baseURL: url)
        } else {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.loadContinuation = cont
            self.watchdog = Task { [weak self] in
                try? await Task.sleep(for: self?.loadTimeout ?? .seconds(25))
                guard let self, !Task.isCancelled else { return }
                // Still waiting after the timeout — abort so the pipeline moves on.
                if let pending = self.loadContinuation {
                    self.loadContinuation = nil
                    self.webView.stopLoading()
                    pending.resume(throwing: ParseError.timedOut)
                }
            }
        }
        watchdog?.cancel()
        watchdog = nil

        let readabilityJS = Self.loadReadabilityScript()
        // Outer wrapper guarantees a non-null result — the async
        // evaluateJavaScript API traps on JS null/undefined.
        let wrapper = """
        (function() {
            var result = (function() {
                try {
                    \(readabilityJS)
                    var docClone = document.cloneNode(true);
                    // Cruft Layer A (docs/parser-cruft-design.md): drop overlay
                    // chrome — sign-in / subscribe modals — from the clone
                    // before Readability sees it. Deliberately tiny and
                    // structural (ARIA dialog semantics only); phrase-level
                    // cruft is handled post-parse in Swift where it is
                    // unit-testable.
                    try {
                        var overlays = docClone.querySelectorAll(
                            '[role="dialog"], [role="alertdialog"], [aria-modal="true"]');
                        for (var oi = 0; oi < overlays.length; oi++) {
                            var ov = overlays[oi];
                            if (ov.parentNode) { ov.parentNode.removeChild(ov); }
                        }
                    } catch (cleanupErr) { /* never fail the parse over cleanup */ }
                    var reader = new Readability(docClone);
                    var article = reader.parse();
                    if (!article) { return null; }
                    // Derive clean paragraph text from the extracted HTML rather
                    // than using Readability's raw textContent. Raw textContent
                    // preserves every whitespace text node between block elements
                    // (source indentation, empty figure slots), which renders as
                    // large gaps in the reader. Walking block-level leaf elements
                    // and joining them with blank lines yields deterministic,
                    // gap-free paragraph text — the offset space for highlights.
                    // Walk block-level leaf elements once, producing BOTH the
                    // gap-free joined text (legacy offset space) AND an ordered
                    // typed block array. The two share a single traversal so the
                    // text and blocks can never drift out of document order.
                    var walked = (function(html) {
                        var BLOCK = { P:1, H1:1, H2:1, H3:1, H4:1, H5:1, H6:1,
                                      LI:1, BLOCKQUOTE:1, PRE:1, FIGCAPTION:1,
                                      DT:1, DD:1, TD:1, TH:1 };
                        var HEADING = { H1:1, H2:2, H3:3, H4:4, H5:5, H6:6 };
                        var container = document.createElement("div");
                        container.innerHTML = html || "";
                        var out = [];
                        var blocks = [];
                        function normalize(s) {
                            return (s || "").replace(/\\s+/g, " ").trim();
                        }
                        function hasBlockChild(el) {
                            for (var i = 0; i < el.children.length; i++) {
                                var c = el.children[i];
                                if (BLOCK[c.tagName] || hasBlockChild(c)) { return true; }
                            }
                            return false;
                        }
                        // A <p> whose entire content is a single <code> element.
                        // Medium marks each line of a multi-line code block this
                        // way (or as per-line <pre> siblings); classifying these
                        // as preformatted lets the Swift side coalesce the run
                        // into one code block instead of inline body text.
                        function isCodeOnly(el) {
                            if (el.tagName !== "P") { return false; }
                            if (el.children.length !== 1) { return false; }
                            if (el.children[0].tagName !== "CODE") { return false; }
                            var codeText = normalize(el.children[0].textContent);
                            return codeText.length > 0 &&
                                   normalize(el.textContent) === codeText;
                        }
                        function nearestListStyle(el) {
                            var p = el.parentElement;
                            while (p && p !== container) {
                                if (p.tagName === "OL") { return "ordered"; }
                                if (p.tagName === "UL") { return "unordered"; }
                                p = p.parentElement;
                            }
                            return null;
                        }
                        function pushImage(img) {
                            if (!img) { return; }
                            var raw = img.getAttribute("src")
                                   || img.getAttribute("data-src") || "";
                            if (!raw) { return; }
                            var src;
                            try { src = new URL(raw, document.baseURI).href; }
                            catch (e) { return; }
                            if (src.indexOf("data:") === 0) { return; }
                            var wAttr = parseInt(img.getAttribute("width"), 10);
                            var hAttr = parseInt(img.getAttribute("height"), 10);
                            // Tracking pixels: explicit 1x1-ish dimensions.
                            if ((!isNaN(wAttr) && wAttr <= 2) ||
                                (!isNaN(hAttr) && hAttr <= 2)) { return; }
                            var b = { type: "image", src: src };
                            var alt = img.getAttribute("alt");
                            if (alt) { b.alt = alt; }
                            var w = !isNaN(wAttr) ? wAttr : (img.naturalWidth || 0);
                            var h = !isNaN(hAttr) ? hAttr : (img.naturalHeight || 0);
                            if (w > 0) { b.width = w; }
                            if (h > 0) { b.height = h; }
                            blocks.push(b);
                        }
                        function walk(el) {
                            for (var i = 0; i < el.children.length; i++) {
                                var child = el.children[i];
                                var tag = child.tagName;
                                if (tag === "HR") {
                                    blocks.push({ type: "divider" });
                                    continue;
                                }
                                if (tag === "FIGURE") {
                                    // Image first, then its caption as a separate
                                    // text-bearing block immediately after.
                                    pushImage(child.querySelector("img"));
                                    var cap = child.querySelector("figcaption");
                                    if (cap) {
                                        var ct = normalize(cap.textContent);
                                        if (ct) {
                                            out.push(ct);
                                            blocks.push({ type: "caption", text: ct });
                                        }
                                    }
                                    continue;
                                }
                                if (tag === "PICTURE") {
                                    pushImage(child.querySelector("img"));
                                    continue;
                                }
                                if (tag === "IMG") {
                                    pushImage(child);
                                    continue;
                                }
                                if (BLOCK[tag] && !hasBlockChild(child)) {
                                    // PRE and code-only <p> keep their internal
                                    // whitespace; everything else collapses runs
                                    // of whitespace to a single space.
                                    var pre = tag === "PRE" || isCodeOnly(child);
                                    var t = pre
                                        ? (child.textContent || "").replace(/\\s+$/,"")
                                        : normalize(child.textContent);
                                    if (t) {
                                        out.push(t);
                                        if (pre) {
                                            blocks.push({ type: "preformatted", text: t });
                                        } else if (HEADING[tag]) {
                                            blocks.push({ type: "heading", text: t, level: HEADING[tag] });
                                        } else if (tag === "LI") {
                                            var lb = { type: "listItem", text: t };
                                            var ls = nearestListStyle(child);
                                            if (ls) { lb.listStyle = ls; }
                                            blocks.push(lb);
                                        } else if (tag === "BLOCKQUOTE") {
                                            blocks.push({ type: "blockquote", text: t });
                                        } else if (tag === "FIGCAPTION") {
                                            blocks.push({ type: "caption", text: t });
                                        } else {
                                            blocks.push({ type: "paragraph", text: t });
                                        }
                                    }
                                    // Images nested inside a leaf block — the
                                    // common <p><img></p> pattern — emit after
                                    // the block's text, in document order.
                                    // textContent never includes images, so the
                                    // legacy text join is unaffected.
                                    var nested = child.querySelectorAll("img");
                                    for (var j = 0; j < nested.length; j++) {
                                        pushImage(nested[j]);
                                    }
                                } else {
                                    walk(child);
                                }
                            }
                        }
                        walk(container);
                        return { text: out.join("\\n\\n"), blocks: blocks };
                    })(article.content);
                    return {
                        title: article.title || document.title || "",
                        byline: article.byline || null,
                        siteName: article.siteName || null,
                        content: article.content || "",
                        text: walked.text || article.textContent || "",
                        blocks: walked.blocks || [],
                        textContent: article.textContent || "",
                        length: article.length || 0,
                        excerpt: article.excerpt || null,
                        heroImage: (function() {
                            var og = document.querySelector('meta[property="og:image"]');
                            return og ? og.content : null;
                        })(),
                        // Fraction of extracted text that lives inside anchors.
                        // A high value on a short result is the signature of a
                        // nav shell (Sitemap / Sign in / Write / Search) rather
                        // than an article, and feeds the Swift quality gate.
                        linkDensity: (function() {
                            var c = document.createElement("div");
                            c.innerHTML = article.content || "";
                            var total = (c.textContent || "").replace(/\\s+/g, "").length;
                            if (!total) { return 1; }
                            var linkChars = 0;
                            var as = c.querySelectorAll("a");
                            for (var i = 0; i < as.length; i++) {
                                linkChars += (as[i].textContent || "").replace(/\\s+/g, "").length;
                            }
                            return linkChars / total;
                        })(),
                        // Raw paywall signals off the LIVE DOM (not the
                        // extracted/filtered clone) — the Swift PaywallDetector
                        // interprets these. `jsonLD` is the text of every
                        // schema.org script; `bodyText` is the visible page text
                        // (capped) scanned for in-DOM gate CTAs.
                        jsonLD: (function() {
                            var out = [];
                            try {
                                var s = document.querySelectorAll(
                                    'script[type="application/ld+json"]');
                                for (var i = 0; i < s.length; i++) {
                                    var txt = s[i].textContent || "";
                                    if (txt) { out.push(txt); }
                                }
                            } catch (e) {}
                            return out;
                        })(),
                        bodyText: (function() {
                            try {
                                var t = (document.body && document.body.innerText)
                                    ? document.body.innerText : "";
                                return t.length > 100000 ? t.slice(0, 100000) : t;
                            } catch (e) { return ""; }
                        })()
                    };
                } catch (e) {
                    return { error: String(e) };
                }
            })();
            return result || { error: "no readable content" };
        })();
        """

        // One extraction pass over the DOM as it stands right now: run the
        // wrapper, decode it, and throw `.lowQuality` if the result reads like a
        // nav shell rather than an article. Re-runnable because the wrapper is a
        // constant string and reads the live DOM each time.
        func runPass() async throws -> Parsed {
            let result = try await webView.evaluateJavaScript(wrapper)
            guard let dict = result as? [String: Any] else {
                throw ParseError.readabilityFailed("non-dictionary result")
            }
            if let err = dict["error"] as? String {
                throw ParseError.readabilityFailed(err)
            }

            let title = (dict["title"] as? String) ?? url.host ?? "Untitled"
            let byline = dict["byline"] as? String
            let siteName = dict["siteName"] as? String
            let html = (dict["content"] as? String) ?? ""
            // Prefer the gap-free block text; fall back to raw textContent if the
            // HTML walk produced nothing (e.g. content without block wrappers).
            let cleaned = (dict["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let legacyText = cleaned.isEmpty
                ? ((dict["textContent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                : cleaned
            let hero = (dict["heroImage"] as? String).flatMap { URL(string: $0) }
            let linkDensity = Self.doubleValue(dict["linkDensity"]) ?? 1

            let rawBlocks = (dict["blocks"] as? [[String: Any]]) ?? []
            let mapped = Self.blocks(fromJS: rawBlocks, baseURL: url)

            // Honest paywall detection (additive — never a gate rejection).
            // Read off the live DOM signals gathered by the wrapper.
            let paywall = PaywallDetector.detect(
                jsonLDBlobs: (dict["jsonLD"] as? [String]) ?? [],
                bodyText: (dict["bodyText"] as? String) ?? ""
            )

            // Cruft Layer B (docs/parser-cruft-design.md): rule-driven removal
            // of subscribe/sign-in nags, social CTA clusters, and "N min read"
            // metadata. Runs AFTER blocks(fromJS:) (post preformatted
            // coalescing) and BEFORE the quality gate, so the gate judges the
            // post-filter article. `gateAndFilter` backs the filter off when
            // removal alone would push a legit borderline-short article below
            // the gate's thresholds. Filtering happens ONLY here, at parse
            // time — never against stored blocks, because plainText derived
            // from the kept blocks is the highlight offset space and
            // re-filtering saved text would shift existing highlight anchors.
            guard let refined = Self.gateAndFilter(
                mapped: mapped, legacyText: legacyText, linkDensity: linkDensity
            ) else {
                // The gate rejected this pass. If it's a paywall, the "missing"
                // content is behind a login the retries can't defeat — stop the
                // loop now instead of burning 40+ seconds re-pumping the same
                // gated page. Otherwise fall through to the normal retry.
                if paywall.isPaywalled { throw ParseError.paywalled }
                throw ParseError.lowQuality
            }
            let blocks = refined.blocks
            let text = refined.plainText

            #if DEBUG
            if !refined.removed.isEmpty {
                NSLog("ArticleParser: cruft filter removed %d of %d blocks for %@",
                      refined.removed.count, mapped.count, url.absoluteString)
            }
            // A preformatted-block divergence is expected: adjacent code
            // lines are coalesced with "\n" whereas the legacy join used
            // "\n\n". Cruft-filtered divergence is expected too (logged
            // above). Only flag genuine drift.
            if text != legacyText, refined.removed.isEmpty, !blocks.isEmpty,
               !blocks.contains(where: { $0.type == .preformatted }) {
                NSLog("ArticleParser: derived plainText differs from legacy join (derived=%d chars, legacy=%d chars) for %@",
                      text.count, legacyText.count, url.absoluteString)
            }
            #endif

            return Parsed(
                title: title,
                author: byline,
                siteName: siteName,
                plainText: text,
                extractedHTML: html,
                heroImageURL: hero,
                estimatedReadingMinutes: max(1, text.split(separator: " ").count / 220),
                blocks: blocks,
                removedBlocks: refined.removed,
                isPaywalledPartial: paywall.isPaywalled
            )
        }

        // Pump the page to a full render, extract, and gate — retrying with a
        // longer settle when a pass looks like a shell. If every attempt fails
        // the gate we surface the error so the caller records `.failed` (user
        // can retry / open in Safari) instead of persisting nav junk.
        var lastError: Error = ParseError.lowQuality
        for attempt in 0 ..< Self.maxParseAttempts {
            await pumpFullRender(longSettle: attempt > 0)
            do {
                return try await runPass()
            } catch ParseError.paywalled {
                // Detected a member-only gate on a pass that also failed the
                // quality gate: retries won't reveal the body. Surface it now.
                NSLog("ArticleParser: paywall gate detected for %@ — short-circuiting retries",
                      url.absoluteString)
                throw ParseError.paywalled
            } catch {
                lastError = error
                NSLog("ArticleParser: parse attempt %d/%d rejected for %@: %@",
                      attempt + 1, Self.maxParseAttempts, url.absoluteString, String(describing: error))
            }
            if attempt + 1 < Self.maxParseAttempts {
                try? await Task.sleep(for: .seconds(Double(attempt + 1) * 1.5))
            }
        }
        throw lastError
    }

    /// Number of extract-and-gate attempts before giving up. Each attempt is
    /// preceded by a full-render pump; later attempts pump longer, which
    /// (together with the inter-attempt backoff) gives a JS-rendered page time
    /// to swap its app shell for the real article.
    private static let maxParseAttempts = 3

    /// One JS pass of the render pump. Steps the scroll position toward the
    /// document bottom (both `scrollTo` and a direct `scrollTop` write — some
    /// engines ignore one or the other off-screen), then dispatches synthetic
    /// `scroll` events for lazy-loaders that listen for events rather than
    /// observing positions, and reports the resulting document metrics.
    private static let pumpPassJS = """
    (function() {
        var se = document.scrollingElement || document.documentElement;
        var vh = window.innerHeight || 1;
        var maxTop = Math.max(0, se.scrollHeight - vh);
        var next = Math.min(se.scrollTop + vh * 3, maxTop);
        try { window.scrollTo(0, next); } catch (e) {}
        se.scrollTop = next;
        try {
            window.dispatchEvent(new Event("scroll"));
            document.dispatchEvent(new Event("scroll"));
        } catch (e) {}
        var t = (document.body && document.body.innerText)
            ? document.body.innerText.length : 0;
        var atBottom = (se.scrollTop + vh) >= (se.scrollHeight - 4);
        return { h: se.scrollHeight, t: t, bottom: atBottom ? 1 : 0 };
    })()
    """

    /// Drives the page to a full render before extraction. JS-heavy sites fire
    /// `didFinish` with only the app shell, and lazy-rendering sites (Medium)
    /// mount below-the-fold content only as it approaches the viewport — an
    /// off-screen WKWebView never scrolls, so without this the DOM "stabilizes"
    /// with just the top of the article and extraction truncates it at a
    /// consistent point. Each pass scroll-steps toward the bottom, nudges lazy
    /// loaders with synthetic scroll events, and samples `scrollHeight` +
    /// `innerText.length`; the pump exits once the bottom is reached and both
    /// metrics are stable across consecutive samples (`FullRenderTracker`).
    /// Capped so a page that never settles (tickers, infinite feeds) still
    /// proceeds to extraction — with a log flagging possible truncation.
    private func pumpFullRender(longSettle: Bool) async {
        let cap: Duration = longSettle ? .seconds(25) : .seconds(20)
        let pollInterval: Duration = .milliseconds(400)
        var tracker = FullRenderTracker(requiredStableSamples: 2)
        var lastHeight = -1
        var lastHeightDelta = 0
        let start = ContinuousClock.now
        while ContinuousClock.now - start < cap {
            guard let sample = await runPumpPass() else {
                try? await Task.sleep(for: pollInterval)
                continue
            }
            if lastHeight >= 0 { lastHeightDelta = sample.scrollHeight - lastHeight }
            lastHeight = sample.scrollHeight
            if tracker.record(
                scrollHeight: sample.scrollHeight,
                textLength: sample.textLength,
                atBottom: sample.atBottom
            ), sample.textLength > 0 {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }
        // Cap hit. If the document was still growing on the final pass the
        // extraction below is likely truncated — flag it for diagnosis. (An
        // infinite feed also lands here; the quality gate still applies.)
        if lastHeightDelta > 0 {
            NSLog("ArticleParser: render pump hit %.0fs cap while scrollHeight was still growing (+%d on last pass) — extraction may be truncated",
                  Double(cap.components.seconds), lastHeightDelta)
        }
    }

    private struct PumpSample {
        let scrollHeight: Int
        let textLength: Int
        let atBottom: Bool
    }

    /// Executes one pump pass and decodes its metrics (nil on any JS failure).
    private func runPumpPass() async -> PumpSample? {
        guard let value = try? await webView.evaluateJavaScript(Self.pumpPassJS),
              let dict = value as? [String: Any],
              let h = Self.intValue(dict["h"]),
              let t = Self.intValue(dict["t"])
        else { return nil }
        return PumpSample(
            scrollHeight: h,
            textLength: t,
            atBottom: (Self.intValue(dict["bottom"]) ?? 0) == 1
        )
    }

    /// Maps and validates the JS block dictionaries into typed `ArticleBlock`s.
    /// Pure — no WKWebView or main-actor state — so it is unit-testable directly.
    ///
    /// Rules: unknown `type` strings are dropped (logged, never fatal); ints may
    /// arrive as `NSNumber`/`Double`; image `src` is resolved against `baseURL`
    /// and images with no src, a `data:` URI, or tracking-pixel dimensions
    /// (width or height ≤ 2) are skipped.
    nonisolated static func blocks(fromJS raw: [[String: Any]], baseURL: URL) -> [ArticleBlock] {
        var result: [ArticleBlock] = []
        for dict in raw {
            guard let typeString = dict["type"] as? String else { continue }
            guard let type = BlockType(rawValue: typeString) else {
                NSLog("ArticleParser: dropping unknown block type %@", typeString)
                continue
            }
            let text = dict["text"] as? String
            let level = intValue(dict["level"])
            let width = intValue(dict["width"])
            let height = intValue(dict["height"])

            switch type {
            case .image:
                guard let srcString = (dict["src"] as? String), !srcString.isEmpty else { continue }
                if srcString.hasPrefix("data:") { continue }
                if let w = width, w <= 2 { continue }
                if let h = height, h <= 2 { continue }
                guard let resolved = URL(string: srcString, relativeTo: baseURL)?.absoluteURL else { continue }
                result.append(ArticleBlock(
                    type: .image,
                    src: resolved,
                    alt: dict["alt"] as? String,
                    width: width,
                    height: height
                ))
            case .heading:
                result.append(ArticleBlock(type: .heading, text: text, level: level))
            case .listItem:
                let listStyle = (dict["listStyle"] as? String).flatMap { ListStyle(rawValue: $0) }
                result.append(ArticleBlock(type: .listItem, text: text, listStyle: listStyle))
            case .divider:
                result.append(ArticleBlock(type: .divider))
            case .paragraph, .blockquote, .preformatted, .caption:
                result.append(ArticleBlock(type: type, text: text))
            }
        }
        return coalescePreformatted(result)
    }

    /// Coalesces runs of consecutive `.preformatted` blocks into a single block
    /// whose lines are joined by "\n". Medium emits a multi-line code block as
    /// per-line `<pre>` / code-only `<p>` siblings; without this each line would
    /// render as its own tiny code block (or, in the flowed reader, as wrapped
    /// body text). A lone preformatted block is returned unchanged (same id and
    /// text), so a single `<pre>` — including one that is already internally
    /// multi-line — is untouched. Pure and order-preserving, so unit-testable.
    nonisolated static func coalescePreformatted(_ blocks: [ArticleBlock]) -> [ArticleBlock] {
        var out: [ArticleBlock] = []
        var run: [ArticleBlock] = []
        func flush() {
            if run.count == 1 {
                out.append(run[0])
            } else if run.count > 1 {
                let joined = run.map { $0.text ?? "" }.joined(separator: "\n")
                out.append(ArticleBlock(type: .preformatted, text: joined))
            }
            run.removeAll()
        }
        for block in blocks {
            if block.type == .preformatted {
                run.append(block)
            } else {
                flush()
                out.append(block)
            }
        }
        flush()
        return out
    }

    /// Robustly coerces a JS-bridged numeric (`NSNumber`, `Int`, `Double`) to `Int`.
    nonisolated static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as NSNumber: return n.intValue
        case let i as Int: return i
        case let d as Double: return Int(d)
        default: return nil
        }
    }

    /// Robustly coerces a JS-bridged numeric to `Double`.
    nonisolated static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        default: return nil
        }
    }

    /// Pure content-quality gate. Rejects near-empty extractions and nav shells
    /// (e.g. "Sitemap Sign in Write Search") so the parse loop retries or fails
    /// instead of persisting junk. No WKWebView / main-actor state — testable.
    enum QualityGate {
        /// Below this word count a result is treated as a shell, not an article.
        static let minimumWords = 50

        static func passes(plainText: String, blocks: [ArticleBlock], linkDensity: Double) -> Bool {
            let words = plainText.split(whereSeparator: { $0.isWhitespace }).count
            if words < minimumWords { return false }
            // Mostly anchors with little prose: site chrome, not a body.
            if linkDensity > 0.5, words < 400 { return false }
            // A handful of short, link-like lines: a nav list, not an article.
            let textBlocks = blocks.filter { $0.type.isTextBearing && !($0.text?.isEmpty ?? true) }
            if !textBlocks.isEmpty, textBlocks.count < 8 {
                let shortish = textBlocks.filter {
                    ($0.text ?? "").split(whereSeparator: { $0.isWhitespace }).count <= 3
                }.count
                if Double(shortish) / Double(textBlocks.count) > 0.6 { return false }
            }
            return true
        }
    }

    /// Composes the cruft filter with the quality gate. Pure — no WKWebView or
    /// main-actor state — so the interaction is unit-testable directly.
    ///
    /// The gate evaluates the POST-filter article (filtered blocks + the
    /// plainText derived from them). If that fails but the UNFILTERED article
    /// would pass, cruft removal alone pushed a borderline-short legit article
    /// below the gate's thresholds — the filter backs off entirely, because
    /// keeping a nag on screen beats rejecting a real article as `.lowQuality`.
    /// Returns nil when even the unfiltered result reads like a nav shell
    /// (caller throws `.lowQuality`).
    ///
    /// When `blocks` is empty the legacy fallback text is used as-is,
    /// unfiltered — deliberately out of scope for the first cut (see
    /// docs/parser-cruft-design.md, "Deferred").
    nonisolated static func gateAndFilter(
        mapped: [ArticleBlock],
        legacyText: String,
        linkDensity: Double
    ) -> (blocks: [ArticleBlock], removed: [ArticleBlock], plainText: String)? {
        // When the typed walk produced text-bearing blocks, plainText is
        // derived from them so it stays byte-identical to the block reader's
        // own view of the text (the highlight offset space). Otherwise keep
        // the legacy join.
        func plainText(for blocks: [ArticleBlock]) -> String {
            guard !blocks.isEmpty else { return legacyText }
            let derived = ArticleBlocks.derivePlainText(blocks)
            return derived.isEmpty ? legacyText : derived
        }

        let filtered = CruftFilter.filter(mapped)
        let filteredText = plainText(for: filtered.kept)
        if QualityGate.passes(plainText: filteredText, blocks: filtered.kept, linkDensity: linkDensity) {
            return (filtered.kept, filtered.removed, filteredText)
        }

        let rawText = plainText(for: mapped)
        if QualityGate.passes(plainText: rawText, blocks: mapped, linkDensity: linkDensity) {
            return (mapped, [], rawText)
        }
        return nil
    }

    /// Pure sampling helper for DOM-stabilization: reports stability once it has
    /// seen `requiredStableSamples` consecutive equal samples. Extracted from the
    /// polling loop so the settle decision is unit-testable without a WKWebView.
    struct StabilityTracker {
        let requiredStableSamples: Int
        private var last: Int?
        private var stableCount = 0

        init(requiredStableSamples: Int) {
            self.requiredStableSamples = max(1, requiredStableSamples)
        }

        /// Feeds one sample; returns true when the current run of equal samples
        /// has reached `requiredStableSamples`.
        mutating func record(_ sample: Int) -> Bool {
            if last == sample {
                stableCount += 1
            } else {
                stableCount = 1
            }
            last = sample
            return stableCount >= requiredStableSamples
        }
    }

    /// Pure settle decision for the full-render pump: the page counts as fully
    /// rendered only when the scroll position has reached the document bottom
    /// AND both `scrollHeight` and rendered-text length are stable across
    /// consecutive samples. Requiring all three prevents the lazy-render trap —
    /// text length going quiet while the still-unscrolled remainder of the
    /// article has simply never been given a reason to mount. Extracted from
    /// the polling loop so it is unit-testable without a WKWebView.
    struct FullRenderTracker {
        private var heightTracker: StabilityTracker
        private var textTracker: StabilityTracker

        init(requiredStableSamples: Int) {
            heightTracker = StabilityTracker(requiredStableSamples: requiredStableSamples)
            textTracker = StabilityTracker(requiredStableSamples: requiredStableSamples)
        }

        /// Feeds one sample; returns true once the render is settled. Both
        /// sub-trackers record unconditionally (no short-circuit) so their
        /// stability runs stay accurate even on not-at-bottom passes.
        mutating func record(scrollHeight: Int, textLength: Int, atBottom: Bool) -> Bool {
            let heightStable = heightTracker.record(scrollHeight)
            let textStable = textTracker.record(textLength)
            return atBottom && heightStable && textStable
        }
    }

    private static func loadReadabilityScript() -> String {
        if let url = Bundle.main.url(forResource: "readability", withExtension: "js"),
           let src = try? String(contentsOf: url, encoding: .utf8) {
            return src
        }
        // Minimal stand-in: monkey-patches a Readability that just yanks <article> / <main> content.
        return """
        var Readability = function(doc) { this.doc = doc; };
        Readability.prototype.parse = function() {
            var el = this.doc.querySelector('article') || this.doc.querySelector('main') || this.doc.body;
            if (!el) return null;
            var title = this.doc.querySelector('h1');
            return {
                title: title ? title.innerText : (this.doc.title || ''),
                byline: null,
                siteName: null,
                content: el.innerHTML,
                textContent: el.innerText,
                length: (el.innerText || '').length,
                excerpt: null
            };
        };
        """
    }

    enum ParseError: LocalizedError {
        case readabilityFailed(String)
        case loadFailed(Error)
        case timedOut
        case busy
        /// Every extract attempt produced a nav shell / near-empty result that
        /// failed the quality gate. Surfaced so the caller records `.failed`.
        case lowQuality
        /// The page is metered/member-only and served only a gate (no readable
        /// preview reached us). Distinct from `.lowQuality` so the caller can
        /// explain *why* there's nothing to show instead of blaming the load.
        case paywalled

        var errorDescription: String? {
            switch self {
            case .readabilityFailed:
                return "The extractor couldn't find readable content on this page."
            case .loadFailed:
                return "The page failed to load."
            case .timedOut:
                return "The page took too long to load."
            case .busy:
                return "Another article is still being parsed. Try again in a moment."
            case .lowQuality:
                return "This page didn't finish loading its article content. Try again."
            case .paywalled:
                return "This article is member-only, so only a preview is available without signing in."
            }
        }
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

extension Article {
    /// Applies a fresh `ArticleParser.Parsed` to this article's derived fields.
    /// Shared by the initial ingest (`PendingSaveIngest`) and the Re-extract
    /// action so the field-write set can never drift between the two paths.
    ///
    /// `updateTitle` is true on first ingest (adopt the parsed title unless it
    /// is empty) and false on Re-extract (the user-visible title stays put).
    /// Highlights are never touched here — they re-anchor lazily on next render.
    /// `parseStatus` is left to the caller (ingest flips it to `.ready`).
    func apply(_ parsed: ArticleParser.Parsed, updateTitle: Bool) {
        if updateTitle, !parsed.title.isEmpty {
            title = parsed.title
        }
        author = parsed.author
        siteName = parsed.siteName
        plainText = parsed.plainText
        if !parsed.blocks.isEmpty {
            try? setBlocks(parsed.blocks)
        }
        extractedHTML = parsed.extractedHTML
        heroImageURL = parsed.heroImageURL
        estimatedReadingMinutes = parsed.estimatedReadingMinutes
        // Debug bookkeeping for the cruft filter (Ellen's review decisions):
        // record whether anything was removed and keep the removed blocks
        // inspectable. Overwritten (or cleared) on every parse so the fields
        // always describe the CURRENT plainText/blocks.
        wasCruftFiltered = !parsed.removedBlocks.isEmpty
        removedCruftJSON = parsed.removedBlocks.isEmpty
            ? nil
            : try? JSONEncoder().encode(parsed.removedBlocks)
        // Overwritten on every parse so the flag always describes the current
        // plainText — a later re-extract that reaches the full article clears it.
        isPaywalledPartial = parsed.isPaywalledPartial
    }
}

extension ArticleParser: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.finishLoad(.success(()))
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.finishLoad(.failure(ParseError.loadFailed(error)))
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.finishLoad(.failure(ParseError.loadFailed(error)))
        }
    }
}
