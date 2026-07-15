import Foundation
@preconcurrency import WebKit

/// Loads the signed-in `youtube.com/feed/channels` page in an off-screen
/// WKWebView — using the **shared** `SiteLoginStore` cookie jar so the session
/// the user just established in `SiteLoginView` is present — scroll-pumps the
/// lazily-rendered subscription grid to the bottom, and harvests the
/// subscribed-channel anchors from the live DOM.
///
/// This is the single most brittle piece in the YouTube feature (see
/// docs/youtube-save-design.md — Wave 2): it scrapes logged-in markup that
/// YouTube can reshape at any time. It is acceptable *only* because the import
/// is one-time and has a stable fallback (Takeout CSV). Accordingly this type
/// fails **loud and fast**: every wait is watchdog-bounded (mirroring
/// `ArticleParser`/`SiteLoginStore` timeout discipline) so a hung or
/// markup-changed page surfaces `HarvestError` rather than an eternal spinner,
/// and the caller then points the user at the CSV path.
///
/// The DOM→channel mapping is deliberately *not* here — the in-page JS only
/// collects raw `{name, href}` anchors, and the pure, fixture-tested
/// `YouTubeSubscriptionImport.channels(fromAnchors:)` classifies them. So the
/// fragile surface (markup shape) is isolated behind a testable seam.
@MainActor
final class YouTubeSubscriptionHarvester: NSObject {

    enum HarvestError: LocalizedError {
        /// The page never finished loading within the deadline.
        case timedOut
        /// The page loaded but yielded no channel anchors — either the user is
        /// not signed in (redirected to a sign-in/consent page) or YouTube
        /// changed the markup. Both resolve to the same user guidance.
        case empty

        var errorDescription: String? {
            switch self {
            case .timedOut:
                return "YouTube took too long to respond. Check your connection and try again, or import from a Google Takeout file instead."
            case .empty:
                return "Couldn't read your subscriptions. Make sure you're signed in to YouTube, or import from a Google Takeout file instead."
            }
        }
    }

    /// The logged-in subscription-management page. A desktop UA keeps YouTube on
    /// this `www` grid instead of redirecting to `m.youtube.com`, whose markup is
    /// different and lacks the same anchor surface.
    private static let channelsURL = URL(string: "https://www.youtube.com/feed/channels")!

    /// Desktop macOS Safari UA. Cookies are domain-keyed (UA-independent), so the
    /// session from the Mobile-Safari-UA login sheet still applies here.
    private static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private let loadTimeout: Duration = .seconds(30)

    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        // Same jar as SiteLoginView / ArticleParser — this is what makes the
        // just-completed login visible to the harvest.
        config.websiteDataStore = SiteLoginStore.shared.dataStore
        config.suppressesIncrementalRendering = true
        // Tall desktop-width viewport so the virtualized channel grid mounts many
        // rows at once; the pump covers the rest.
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 4000), configuration: config)
        wv.customUserAgent = desktopUserAgent
        return wv
    }()

    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var watchdog: Task<Void, Never>?

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads the subscription page, pumps it, and returns the harvested channels.
    /// Throws `HarvestError.timedOut` if the page never loads and `.empty` if it
    /// loads but no channels can be read. Never suspends indefinitely.
    ///
    /// `prefetchedHTML` exists purely so tests can drive the load path against a
    /// captured page without the network; production callers omit it.
    func harvest(prefetchedHTML: String? = nil) async throws -> [ImportableChannel] {
        if let html = prefetchedHTML {
            webView.loadHTMLString(html, baseURL: Self.channelsURL)
        } else {
            webView.load(URLRequest(url: Self.channelsURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
        }

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.loadContinuation = cont
                self.watchdog = Task { [weak self] in
                    try? await Task.sleep(for: self?.loadTimeout ?? .seconds(30))
                    guard let self, !Task.isCancelled else { return }
                    if let pending = self.loadContinuation {
                        self.loadContinuation = nil
                        self.webView.stopLoading()
                        pending.resume(throwing: HarvestError.timedOut)
                    }
                }
            }
        } catch {
            watchdog?.cancel(); watchdog = nil
            throw error
        }
        watchdog?.cancel(); watchdog = nil

        await pumpUntilStable()

        let anchors = await collectAnchors()
        let channels = YouTubeSubscriptionImport.channels(fromAnchors: anchors)
        if channels.isEmpty { throw HarvestError.empty }
        return channels
    }

    // MARK: - Scroll pump

    /// Scroll-steps the virtualized subscription grid to the bottom, nudging
    /// lazy-loaders with synthetic scroll events, until the harvested anchor
    /// count stops growing across consecutive samples or a cap is hit. Same
    /// philosophy as `ArticleParser.pumpFullRender`, scoped to a channel count
    /// rather than article text. Bounded so a page that never settles still
    /// proceeds to the harvest.
    private func pumpUntilStable() async {
        let pollInterval: Duration = .milliseconds(400)
        let hardCap: Duration = .seconds(20)
        let start = ContinuousClock.now
        var lastCount = -1
        var stableSamples = 0
        while ContinuousClock.now - start < hardCap {
            let count = await runPumpPass()
            if count == lastCount {
                stableSamples += 1
                if stableSamples >= 2, count > 0 { return }
            } else {
                stableSamples = 0
                lastCount = count
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// One pump pass: scrolls toward the bottom, fires scroll events, and returns
    /// the current count of candidate channel anchors (nil-safe → 0 on failure).
    private func runPumpPass() async -> Int {
        let value = try? await webView.evaluateJavaScript(Self.pumpPassJS)
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static let pumpPassJS = """
    (function() {
      var se = document.scrollingElement || document.documentElement;
      var vh = window.innerHeight || 800;
      var next = Math.min(se.scrollTop + vh * 3, Math.max(0, se.scrollHeight - vh));
      try { window.scrollTo(0, next); } catch (e) {}
      se.scrollTop = next;
      try {
        window.dispatchEvent(new Event('scroll'));
        document.dispatchEvent(new Event('scroll'));
      } catch (e) {}
      return document.querySelectorAll('a[href^="/channel/"], a[href^="/@"], a[href^="/c/"], a[href^="/user/"]').length;
    })();
    """

    // MARK: - Anchor harvest

    /// Reads every candidate channel link out of the rendered DOM as
    /// `{name, href}` dictionaries. `name` prefers the accessible label
    /// (`aria-label`/`title`) and falls back to trimmed link text; empty-text
    /// avatar links still come through (classified and deduped by the pure seam).
    private func collectAnchors() async -> [[String: String]] {
        let value = try? await webView.evaluateJavaScript(Self.collectAnchorsJS)
        guard let raw = value as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let href = dict["href"] as? String else { return nil }
            let name = (dict["name"] as? String) ?? ""
            return ["href": href, "name": name]
        }
    }

    private static let collectAnchorsJS = """
    (function() {
      var out = [];
      var links = document.querySelectorAll('a[href^="/channel/"], a[href^="/@"], a[href^="/c/"], a[href^="/user/"], a[href*="youtube.com/channel/"], a[href*="youtube.com/@"]');
      for (var i = 0; i < links.length; i++) {
        var a = links[i];
        var name = a.getAttribute('aria-label') || a.getAttribute('title') || (a.textContent || '').trim();
        out.push({ href: a.getAttribute('href') || a.href || '', name: name });
      }
      return out;
    })();
    """
}

extension YouTubeSubscriptionHarvester: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loadContinuation?.resume()
            self.loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeOnRealFailure(error)
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeOnRealFailure(error)
    }

    /// YouTube routinely cancels its first provisional navigation (consent
    /// interstitial, `?app=desktop`, m↔www redirect) and supersedes it — the same
    /// pattern `VideoArticleParser` handles. Treat `NSURLErrorCancelled` as
    /// non-fatal so a superseded navigation doesn't abort the harvest before
    /// `didFinish`; only genuine failures resume with an error.
    nonisolated private func resumeOnRealFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in
            self.loadContinuation?.resume(throwing: YouTubeSubscriptionHarvester.HarvestError.timedOut)
            self.loadContinuation = nil
        }
    }
}
