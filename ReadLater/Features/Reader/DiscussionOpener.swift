import SafariServices
import SwiftUI
import UIKit

/// Opens a discussion permalink (Reddit comments URL) honouring the user's
/// "Open discussions in" preference. System Default and Narwhal hand off to
/// another app via `UIApplication.open`; the in-app browser is presented by the
/// reader (this helper only reports that intent).
@MainActor
enum DiscussionOpener {

    /// Result of a resolve: either open the given URL externally, or present the
    /// in-app browser with the permalink.
    enum Action {
        case openExternally(URL)
        case presentInApp(URL)
    }

    /// Decides how to open `permalink` for `preference`, falling back to the
    /// reddit.com URL when the preferred app isn't installed.
    static func resolve(
        permalink: URL,
        preference: RedditDiscussionApp
    ) -> Action {
        switch preference {
        case .systemDefault:
            return .openExternally(permalink)
        case .inApp:
            return .presentInApp(permalink)
        case .narwhal:
            if let narwhal = RedditFeed.narwhalURL(forPermalink: permalink),
               UIApplication.shared.canOpenURL(narwhal) {
                return .openExternally(narwhal)
            }
            // Narwhal not installed — hand the reddit.com URL to the OS.
            return .openExternally(permalink)
        }
    }

    /// Opens `permalink` per `preference`. Returns a non-nil URL when the reader
    /// should instead present the in-app browser for it.
    @discardableResult
    static func open(permalink: URL, preference: RedditDiscussionApp) -> URL? {
        switch resolve(permalink: permalink, preference: preference) {
        case .openExternally(let url):
            UIApplication.shared.open(url)
            return nil
        case .presentInApp(let url):
            return url
        }
    }

    /// Always opens `permalink` in the system browser (Safari), regardless of
    /// preference — backs the long-press "Open in Browser" action.
    static func openInBrowser(_ permalink: URL) {
        UIApplication.shared.open(permalink)
    }
}

/// Thin `SFSafariViewController` wrapper for the in-app browser option.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
