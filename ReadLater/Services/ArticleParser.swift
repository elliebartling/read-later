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
    }

    static let shared = ArticleParser()

    private let loadTimeout: Duration = .seconds(25)

    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let wv = WKWebView(frame: .zero, configuration: config)
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
                                    // PRE keeps its internal whitespace; everything
                                    // else collapses runs of whitespace to one space.
                                    var t = tag === "PRE"
                                        ? (child.textContent || "").replace(/\\s+$/,"")
                                        : normalize(child.textContent);
                                    if (t) {
                                        out.push(t);
                                        if (HEADING[tag]) {
                                            blocks.push({ type: "heading", text: t, level: HEADING[tag] });
                                        } else if (tag === "LI") {
                                            var lb = { type: "listItem", text: t };
                                            var ls = nearestListStyle(child);
                                            if (ls) { lb.listStyle = ls; }
                                            blocks.push(lb);
                                        } else if (tag === "BLOCKQUOTE") {
                                            blocks.push({ type: "blockquote", text: t });
                                        } else if (tag === "PRE") {
                                            blocks.push({ type: "preformatted", text: t });
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
                        })()
                    };
                } catch (e) {
                    return { error: String(e) };
                }
            })();
            return result || { error: "no readable content" };
        })();
        """

        let result = try await webView.evaluateJavaScript(wrapper)
        guard let dict = result as? [String: Any] else {
            return fallback(url: url, title: (result as? String) ?? url.host ?? "Untitled")
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

        let rawBlocks = (dict["blocks"] as? [[String: Any]]) ?? []
        let blocks = Self.blocks(fromJS: rawBlocks, baseURL: url)

        // When the typed walk produced text-bearing blocks, plainText is derived
        // from them so it stays byte-identical to the block reader's own view of
        // the text (the highlight offset space). Otherwise keep the legacy join.
        let text: String
        if blocks.isEmpty {
            text = legacyText
        } else {
            let derived = ArticleBlocks.derivePlainText(blocks)
            #if DEBUG
            if derived != legacyText {
                NSLog("ArticleParser: derived plainText differs from legacy join (derived=%d chars, legacy=%d chars) for %@",
                      derived.count, legacyText.count, url.absoluteString)
            }
            #endif
            text = derived.isEmpty ? legacyText : derived
        }

        return Parsed(
            title: title,
            author: byline,
            siteName: siteName,
            plainText: text,
            extractedHTML: html,
            heroImageURL: hero,
            estimatedReadingMinutes: max(1, text.split(separator: " ").count / 220),
            blocks: blocks
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
        return result
    }

    /// Robustly coerces a JS-bridged numeric (`NSNumber`, `Int`, `Double`) to `Int`.
    nonisolated private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as NSNumber: return n.intValue
        case let i as Int: return i
        case let d as Double: return Int(d)
        default: return nil
        }
    }

    private func fallback(url: URL, title: String) -> Parsed {
        Parsed(
            title: title,
            author: nil,
            siteName: url.host,
            plainText: "",
            extractedHTML: "",
            heroImageURL: nil,
            estimatedReadingMinutes: 0,
            blocks: []
        )
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

    enum ParseError: Error {
        case readabilityFailed(String)
        case loadFailed(Error)
        case timedOut
        case busy
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
