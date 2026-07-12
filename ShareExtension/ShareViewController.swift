import UIKit
import Social
import UniformTypeIdentifiers

/// Minimal share sheet UI: pulls the URL (and, if available, the current
/// page's title) out of the incoming extension context, writes a PendingSave
/// JSON into the App Group container, tries to hop straight into the main app
/// at the reader via `readlater://open?id=<pending-save-uuid>`, then dismisses.
///
/// The main app's `RootView.handleDeepLink` drains PendingSaves before setting
/// `AppModel.pendingArticleToOpen`, so LibraryView finds the freshly-inserted
/// stub Article and pushes ReaderView immediately (parse continues in the
/// background; the reader shows a loading state until it lands).
///
/// If the system won't let the extension open the app, the save still lands in
/// the App Group queue — the app ingests it on the next foreground, so the
/// article shows up regardless. The auto-open is a best-effort convenience, not
/// the mechanism the save depends on.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Saving to Read Later…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await capture() }
    }

    private func capture() async {
        // A missing App Group is the silent killer: without it the extension
        // writes to its own sandbox and the app can't see the save. Surface it
        // instead of pretending it worked.
        guard AppGroup.hasSharedContainer else {
            await finish(message: "Read Later isn't set up to receive shares (App Group unavailable).",
                         success: false)
            return
        }

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            await finish(message: "Nothing to save.", success: false)
            return
        }

        var capturedURL: URL?
        var capturedTitle: String?

        // Activation rule is WebURL-only, so a plain URL attachment is all we
        // get here. HTML capture comes via the Safari Web Extension path;
        // otherwise ArticleParser refetches the page itself.
        for item in items {
            if let title = item.attributedTitle?.string, capturedTitle == nil {
                capturedTitle = title
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), capturedURL == nil {
                    if let obj = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                       let url = obj as? URL {
                        capturedURL = url
                    }
                }
            }
        }

        guard let url = capturedURL else {
            await finish(message: "Couldn't find a link to save.", success: false)
            return
        }

        let pending = PendingSave(
            url: url,
            title: capturedTitle,
            source: .shareExtension
        )
        do {
            try pending.write()
        } catch {
            await finish(message: "Couldn't save this link.", success: false)
            return
        }

        // Best-effort hop into the app at the reader. Whether or not this
        // succeeds, the save is already queued.
        let opened = await openContainingApp(articleID: pending.id)
        if opened {
            // The app is coming to the foreground; hand off cleanly.
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            await finish(message: "Saved to Read Later", success: true)
        }
    }

    /// Asks the system to open `readlater://open?id=<uuid>` in the containing
    /// app. Prefers `NSExtensionContext.open` — the sanctioned API — and falls
    /// back to walking the responder chain for a legacy `openURL:` responder,
    /// which is how older iOS reaches `UIApplication` from an extension.
    /// Returns whether either path reported success.
    private func openContainingApp(articleID: UUID) async -> Bool {
        var comps = URLComponents()
        comps.scheme = AppGroup.urlScheme
        comps.host = AppGroup.openDeepLinkHost
        comps.queryItems = [URLQueryItem(name: "id", value: articleID.uuidString)]
        guard let deepLink = comps.url else { return false }

        if let ctx = extensionContext {
            let opened = await withCheckedContinuation { continuation in
                ctx.open(deepLink) { success in continuation.resume(returning: success) }
            }
            if opened { return true }
        }

        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self as UIResponder
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: deepLink)
                return true
            }
            responder = r.next
        }
        return false
    }

    /// Shows a short-lived outcome message, then dismisses. The delay is tied
    /// to the message the user needs to read — not to any launch race — so the
    /// sheet never tears down before the save/open has actually happened.
    private func finish(message: String, success: Bool) async {
        statusLabel.text = message
        let delay: UInt64 = success ? 500_000_000 : 1_500_000_000
        try? await Task.sleep(nanoseconds: delay)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
