import UIKit
import Social
import UniformTypeIdentifiers

/// Minimal share sheet UI: pulls the URL (and, if available, the current
/// page's title) out of the incoming extension context, writes a PendingSave
/// JSON into the App Group container, then offers an "Open Read Later" button
/// and auto-dismisses.
///
/// Design note — the open is button-only, never automatic: a *share* extension
/// has no dependable public API to launch its containing app on its own.
/// `extensionContext.open` is documented for Today widgets and its completion
/// handler frequently never fires for share extensions (awaiting it once hung
/// this sheet). A user-initiated open from the button tap is the sanctioned,
/// reliably-honored path. The save never depends on opening the app either
/// way: the PendingSave lands in the App Group queue and the app drains it on
/// its next foreground.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private var pendingDeepLink: URL?
    private var autoDismiss: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Saving to Read Later…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        openButton.setTitle("Open Read Later", for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        openButton.isHidden = true
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [statusLabel, openButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
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
            finish(message: "Read Later isn't set up to receive shares (App Group unavailable).",
                   showOpen: false, delay: 2.5)
            return
        }

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(message: "Nothing to save.", showOpen: false, delay: 2.0)
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
            finish(message: "Couldn't find a link to save.", showOpen: false, delay: 2.0)
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
            finish(message: "Couldn't save this link.", showOpen: false, delay: 2.0)
            return
        }

        // The save is now safely queued. Offer the button to jump into the app
        // at this article; if untapped, the sheet dismisses on its own.
        pendingDeepLink = openDeepLink(articleID: pending.id)
        finish(message: "Saved to Read Later", showOpen: true, delay: 5.0)
    }

    private func openDeepLink(articleID: UUID) -> URL? {
        var comps = URLComponents()
        comps.scheme = AppGroup.urlScheme
        comps.host = AppGroup.openDeepLinkHost
        comps.queryItems = [URLQueryItem(name: "id", value: articleID.uuidString)]
        return comps.url
    }

    /// Open attempt, only ever invoked from the button tap. Tries the
    /// sanctioned API first, then the legacy responder-chain walk. Neither
    /// call is awaited, so nothing can stall the sheet if the system ignores
    /// the request.
    private func attemptOpen() {
        guard let deepLink = pendingDeepLink else { return }
        extensionContext?.open(deepLink, completionHandler: nil)

        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self as UIResponder
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: deepLink)
                break
            }
            responder = r.next
        }
    }

    @objc private func openTapped() {
        autoDismiss?.cancel()
        attemptOpen()
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Shows an outcome, optionally reveals the Open button, and schedules a
    /// dismiss so the sheet never lingers. All UI work; no awaits that can hang.
    private func finish(message: String, showOpen: Bool, delay: TimeInterval) {
        statusLabel.text = message
        openButton.isHidden = !showOpen
        let work = DispatchWorkItem { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        autoDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
