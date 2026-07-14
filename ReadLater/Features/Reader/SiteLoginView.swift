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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Observable progress/loading state surfaced by the login web view so the
/// SwiftUI progress bar can track the real navigation.
@MainActor
@Observable
final class SiteLoginWebModel {
    var progress: Double = 0
    var isLoading = false
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
        webView.allowsBackForwardNavigationGestures = true
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
