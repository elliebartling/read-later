import UIKit
import Social
import UniformTypeIdentifiers

/// Minimal share sheet UI: pulls the URL (and, if available, the current
/// page's HTML) out of the incoming extension context, writes a PendingSave
/// JSON into the App Group container, kicks the main app open at the reader
/// via `readlater://open?id=<pending-save-uuid>`, then dismisses.
///
/// The main app's `RootView.handleDeepLink` drains PendingSaves before setting
/// `AppModel.pendingArticleToOpen`, so LibraryView finds the freshly-inserted
/// stub Article and pushes ReaderView immediately (parse continues in the
/// background; the reader shows a loading state until it lands).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Saving to Read Later…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await capture() }
    }

    private func capture() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }
        var capturedURL: URL?
        var capturedTitle: String?
        var capturedHTML: String?

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
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier), capturedHTML == nil {
                    if let obj = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier),
                       let dict = obj as? [String: Any],
                       let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                    {
                        capturedHTML = results["html"] as? String
                        if capturedURL == nil, let urlStr = results["url"] as? String {
                            capturedURL = URL(string: urlStr)
                        }
                        if capturedTitle == nil {
                            capturedTitle = results["title"] as? String
                        }
                    }
                }
            }
        }

        if let url = capturedURL {
            let pending = PendingSave(
                url: url,
                title: capturedTitle,
                capturedHTML: capturedHTML,
                source: .shareExtension
            )
            try? pending.write()
            openContainingApp(articleID: pending.id)
        }
        complete()
    }

    /// Uses the responder-chain trick to reach the extension's own
    /// `UIApplication` and dispatch `openURL:`. Share extensions can't touch
    /// `UIApplication.shared` directly (linker refuses), but they can walk the
    /// responder chain to find one that responds to the legacy openURL:
    /// selector — this is the widely-used pattern for share-to-open flows.
    private func openContainingApp(articleID: UUID) {
        var comps = URLComponents()
        comps.scheme = AppGroup.urlScheme
        comps.host = AppGroup.openDeepLinkHost
        comps.queryItems = [URLQueryItem(name: "id", value: articleID.uuidString)]
        guard let deepLink = comps.url else { return }

        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self as UIResponder
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: deepLink)
                return
            }
            responder = r.next
        }
    }

    private func complete() {
        // Small delay so the openURL: dispatched above has a chance to fire
        // before the extension host tears us down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
