import SwiftUI
import UIKit

// Third-party brand representation (§6) — "faithful enough to recognise
// instantly, in-system enough to sit in a column", and never heavier than the
// article (N1).
//
//  - **BR1** a favicon is ALWAYS tiled: a 20pt mark centred on a 28pt
//    `Surface.control` tile, 6pt corner. The tile is what makes a ragged
//    collection of transparent PNGs, wrong aspect ratios and near-black logos
//    read as one column. A bare favicon on the page ground is a violation.
//  - **BR2** no favicon → a monogram on a 28pt circle filled with that
//    source's `Source.*` hue, glyph in `Accent.onFill` (A2 — never white).
//  - **BR5** the hue is row identity only. It never tints text, selection,
//    controls, or `Accent.*`.

enum SourceIdentity {

    /// Host with `www.` stripped — the string half of source identity.
    static func strippingWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The monogram for a source: the first letter or digit of its title,
    /// uppercased. Falls back to the host, then to a placeholder, so a row can
    /// always render something.
    static func monogram(title: String?, host: String?) -> String {
        for candidate in [title, host.map(strippingWWW)] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            if let first = value.first(where: { $0.isLetter || $0.isNumber }) {
                return String(first).uppercased()
            }
        }
        return "•"
    }

    /// **BR5.** Source-kind hue for a saved article, derived from its URL.
    /// Reuses the sidebar's classifier so a YouTube row is the same red in
    /// every list.
    static func tint(for url: URL?) -> Color {
        FeedSourceKind.kind(feedURL: nil, siteURL: url).tint
    }
}

/// **BR1 / BR2.** The row identity mark: a tiled favicon, with a monogram
/// standing in until one arrives (and permanently, for the many sites that
/// ship none).
struct FaviconTile: View {
    /// Host to fetch the icon from. Nil renders the monogram only.
    let host: String?
    /// Source title, for the monogram.
    let title: String?
    /// **BR5.** The source-kind hue behind the monogram.
    let tint: Color

    @State private var icon: UIImage?

    init(host: String?, title: String?, tint: Color) {
        self.host = host
        self.title = title
        self.tint = tint
    }

    /// Convenience for a saved article: host, site name and hue all come off
    /// the article's URL.
    init(article: Article) {
        self.init(
            host: article.url?.host,
            title: article.siteName ?? article.url?.host,
            tint: SourceIdentity.tint(for: article.url)
        )
    }

    var body: some View {
        ZStack {
            if let icon {
                // BR1 — 20pt mark on a 28pt tile. `.fit` so a wide or tall
                // icon is letterboxed by the tile rather than cropped.
                RoundedRectangle(cornerRadius: Radius.faviconTile, style: .continuous)
                    .fill(Surface.control)
                    .overlay {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Metric.faviconMark, height: Metric.faviconMark)
                    }
                    .clipShape(.rect(cornerRadius: Radius.faviconTile, style: .continuous))
            } else {
                // BR2 — monogram fallback.
                Circle()
                    .fill(tint)
                    .overlay {
                        Text(SourceIdentity.monogram(title: title, host: host))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Accent.onFill)
                    }
            }
        }
        // §7.1 small tier. Not interactive on its own, so no 44pt padding —
        // it rides the row's tap target.
        .frame(width: Metric.faviconTile, height: Metric.faviconTile)
        // §10 Micro — the monogram→favicon swap is a glyph swap.
        .animation(.easeOut(duration: 0.18), value: icon != nil)
        .accessibilityHidden(true)
        .task(id: host) {
            guard let host, !host.isEmpty else { return }
            icon = await FaviconStore.shared.icon(for: host)
        }
    }
}
