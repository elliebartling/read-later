import SwiftUI
import UIKit

/// Toolbar affordance for a media post whose media the reader cannot show
/// in full: a `v.redd.it` video (we render its poster frame, not a player) or
/// a Reddit gallery (the RSS surface exposes only the cover image — the rest
/// needs the Reddit API, see docs/reddit-media-posts.md).
///
/// Image posts get nothing here on purpose: the reader already shows the
/// full-resolution asset and `ImageBlockView` zooms it.
///
/// Its own file so the wire-in inside `ReaderView`'s toolbar is three lines,
/// and so the glyph call site doesn't collide with in-flight icon work.
struct MediaPlaybackToolbarItem: ToolbarContent {
    let kind: MediaKind
    let url: URL

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                UIApplication.shared.open(url)
            } label: {
                Image(systemName: symbol).uiGlyph()
            }
            .accessibilityLabel(label)
        }
    }

    // BR4 — a plain system verb, never a brand mark.
    private var symbol: String {
        switch kind {
        case .video: return "play.circle"
        case .gallery: return "square.on.square"
        case .image: return "photo"
        }
    }

    private var label: String {
        switch kind {
        case .video: return "Play video"
        case .gallery: return "See all images"
        case .image: return "Open image"
        }
    }
}
