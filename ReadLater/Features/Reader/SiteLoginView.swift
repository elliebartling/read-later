import SwiftUI
@preconcurrency import WebKit

/// Full-page web view for signing into a site on its **own** pages. We never see
/// or handle credentials — the user signs in exactly as they would in Safari,
/// and the resulting session cookies persist in the shared `SiteLoginStore` data
/// store, so the next article extraction (`ArticleParser`, same store) is
/// authenticated. Presented from the reader's "member-only" banner.
///
/// The re-extract that turns a preview into the full article is driven by the
/// presenter's `.sheet(onDismiss:)`, so it fires however the sheet closes
/// (Done button or swipe-down) — this view just hosts the login.
///
/// The web view advertises itself as Mobile Safari (`MobileSafariUserAgent`).
/// A bare `WKWebView` sends an embedded-webview UA, which Google's OAuth rejects
/// with "Access blocked … 'Use secure browsers' policy — Error 403:
/// disallowed_useragent"; the Safari UA gets past that so "Sign in with Google"
/// reaches its email/password form.
struct SiteLoginView: View {
    /// Where to start the login flow. The article URL is preferred over the site
    /// root: on metered sites (Medium) the article page itself carries the most
    /// discoverable "sign in" affordance, and cookies set anywhere on the host
    /// apply to the whole host.
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var model = SiteLoginWebModel()

    private var host: String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        NavigationStack {
            SiteLoginWebViewRepresentable(url: url, model: model)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.isLoading {
                        ProgressView(value: model.progress)
                            .progressViewStyle(.linear)
                            .transition(.opacity)
                    }
                }
                .animation(.default, value: model.isLoading)
                .navigationTitle(host)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Magic-link escape hatch: some sites (Medium's "Sign in
                    // with email") send a one-time sign-in *link*. Tapped in
                    // Mail it opens Safari, landing cookies in the wrong jar.
                    // Pasting it here loads it in this sheet's web view so the
                    // cookies land in the shared `SiteLoginStore` instead.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            model.loadPastedSignInLink()
                        } label: {
                            Label("Paste sign-in link", systemImage: "link")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert("No sign-in link found", isPresented: $model.showsPasteHelp) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Copy the sign-in link from your email, then tap \"Paste sign-in link\" again to open it here so you stay signed in.")
                }
        }
    }
}

/// Builds a Mobile Safari user-agent string for the running iOS version so the
/// login web view is indistinguishable from Safari to the sites it loads.
///
/// **Why the full string, not `applicationNameForUserAgent`:** setting the
/// configuration's `applicationNameForUserAgent` only *appends* a token after
/// WebKit's default `… Mobile/15E148`, yielding `… Mobile/15E148 Version/26.0
/// Safari/604.1` — the `Version/` token in the wrong place. Real Safari emits
/// `… Version/26.0 Mobile/15E148 Safari/604.1`. Google's OAuth interstitial
/// keys off exactly these tokens, so we set the complete `customUserAgent` and
/// match the real token order. The OS version is read from `UIDevice` at
/// runtime rather than hard-coded so the string never goes stale across iOS
/// releases.
enum MobileSafariUserAgent {
    /// e.g. `Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)
    /// AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148
    /// Safari/604.1`
    static var current: String {
        // Safari reports major.minor only (e.g. "26.0" even on "26.0.1"), with
        // the platform token underscored ("26_0"). Take the first two
        // components and default the minor to 0 when the OS reports a bare major.
        let components = UIDevice.current.systemVersion.split(separator: ".")
        let major = components.first.map(String.init) ?? "26"
        let minor = components.count > 1 ? String(components[1]) : "0"
        let dotted = "\(major).\(minor)"
        let underscored = "\(major)_\(minor)"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(underscored) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(dotted) Mobile/15E148 Safari/604.1"
    }
}

/// Observable progress/loading state surfaced by the login web view so the
/// SwiftUI progress bar can track the real navigation, plus the seam the paste
/// affordance uses to drive the same web view.
@MainActor
@Observable
final class SiteLoginWebModel {
    var progress: Double = 0
    var isLoading = false
    /// Drives the brief "no link on the clipboard" helper alert.
    var showsPasteHelp = false

    /// The sheet's live web view, set by the representable in `makeUIView`. Weak
    /// so the model never keeps the web view alive past the sheet.
    weak var webView: WKWebView?

    /// Loads an http(s) URL from the general pasteboard into the login web view,
    /// keeping magic-link session cookies in the shared `SiteLoginStore`. Shows
    /// a short helper alert when the clipboard holds nothing usable. Reading the
    /// pasteboard triggers the standard iOS paste-permission prompt, which is
    /// expected here.
    func loadPastedSignInLink() {
        guard let url = Self.httpURLFromPasteboard() else {
            showsPasteHelp = true
            return
        }
        webView?.load(URLRequest(url: url))
    }

    /// Extracts the first http(s) URL from the general pasteboard, tolerating
    /// both a real URL item and a pasted string. Junk (non-URL text, `mailto:`,
    /// `javascript:`, empty) yields `nil` so the caller can fall back to help.
    private static func httpURLFromPasteboard() -> URL? {
        let pasteboard = UIPasteboard.general
        // `hasURLs` / `hasStrings` are detection probes and don't trip the paste
        // prompt; only reading `urls` / `string` below does.
        if pasteboard.hasURLs, let url = pasteboard.urls?.first, url.isHTTP {
            return url
        }
        if let string = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: string), url.isHTTP {
            return url
        }
        return nil
    }
}

private extension URL {
    /// True only for `http`/`https` — the schemes safe to load in the web view.
    var isHTTP: Bool {
        switch scheme?.lowercased() {
        case "http", "https": true
        default: false
        }
    }
}

/// Bridges a `WKWebView` into SwiftUI for the login sheet. Configured with the
/// shared `SiteLoginStore.dataStore` so any cookies the site sets during login
/// persist into the same jar the parser reads.
private struct SiteLoginWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let model: SiteLoginWebModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = SiteLoginStore.shared.dataStore
        let webView = WKWebView(frame: .zero, configuration: config)
        // Present as Mobile Safari so OAuth providers (notably Google) don't
        // block the flow as an embedded webview. See `MobileSafariUserAgent`.
        webView.customUserAgent = MobileSafariUserAgent.current
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    /// Retains the KVO tokens for the web view's progress/loading and forwards
    /// changes onto the main actor into the observable model.
    @MainActor
    final class Coordinator {
        private let model: SiteLoginWebModel
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?

        init(model: SiteLoginWebModel) { self.model = model }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [model] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in model.progress = value }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [model] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in model.isLoading = value }
            }
        }
    }
}
