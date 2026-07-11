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
                    return {
                        title: article.title || document.title || "",
                        byline: article.byline || null,
                        siteName: article.siteName || null,
                        content: article.content || "",
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
        let text = (dict["textContent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hero = (dict["heroImage"] as? String).flatMap { URL(string: $0) }

        return Parsed(
            title: title,
            author: byline,
            siteName: siteName,
            plainText: text,
            extractedHTML: html,
            heroImageURL: hero,
            estimatedReadingMinutes: max(1, text.split(separator: " ").count / 220)
        )
    }

    private func fallback(url: URL, title: String) -> Parsed {
        Parsed(
            title: title,
            author: nil,
            siteName: url.host,
            plainText: "",
            extractedHTML: "",
            heroImageURL: nil,
            estimatedReadingMinutes: 0
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
