import UIKit
import Social
import UniformTypeIdentifiers

/// Minimal share sheet UI: pulls the URL (and, if available, the current
/// page's HTML) out of the incoming extension context, writes a PendingSave
/// JSON into the App Group container, and dismisses. The main app drains
/// the queue on next foreground.
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
        }
        complete()
    }

    private func complete() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
