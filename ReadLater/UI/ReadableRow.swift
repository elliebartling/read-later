import SwiftUI
import UIKit

// §8.1 — the list row, one grammar.
//
// Before this, Library and Feeds shared nothing: two unread signals (title
// colour here, a blue dot AND a title colour there), two metadata grammars
// (SF Symbol + label pairs here, bare space-separated text there), two source
// formats, thumbnails in one and not the other, and a hidden `NavigationLink`
// in a `ZStack` so one of them had no disclosure at all. They are the same
// information class — "things you might read" — so they get one component.
//
//     [unread rail] [ title (2 lines max) ]                [thumbnail]
//                   [ summary (2 lines, optional) ]        [ 96×54 ]
//                   [ meta · meta · meta ]
//
// Library, All Items, per-feed lists and Search all render this. The source
// identity mark (BR1/BR2, wave 3) rides in the `identity` slot, between the
// rail and the text column.

/// **R2.** The metadata line: one `.caption` line, `Ink.tertiary`, fields
/// joined by `" · "`, no glyphs (I5). The field order is fixed and identical
/// on every screen — `source · relative date · duration/count` — and a field
/// that duplicates the screen's nav title is simply omitted by the call site
/// (a per-feed list passes `source: nil`).
///
/// It is a value type rather than free-form text so the order cannot drift:
/// the audit found All Items rendering `feed · date · author` and a per-feed
/// list rendering `date · author` from the *same* component.
struct RowMetadata: Equatable {
    /// **R3.** The source string, from `SourceIdentity.sourceString`. Nil when
    /// it would repeat the screen's title.
    var source: String?
    /// Rendered as a named relative date ("3 hours ago").
    var date: Date?
    /// The third field class — duration, count, kind. Several may appear
    /// ("33 min", "2 highlights"); they stay in this slot, after the date.
    var details: [String] = []
    /// **R7.** A failed parse is visible in the list: the meta line leads with
    /// a `Semantic.warning` glyph, the one glyph I5 permits here, because no
    /// text field carries that meaning.
    var isFailed = false

    /// The joined line. Pure, so the grammar is unit-testable.
    var text: String {
        var fields: [String] = []
        if isFailed { fields.append("Couldn't parse") }
        if let source, !source.isEmpty { fields.append(source) }
        if let date { fields.append(date.formatted(.relative(presentation: .named))) }
        fields.append(contentsOf: details.filter { !$0.isEmpty })
        return fields.joined(separator: " · ")
    }
}

/// **R4.** The trailing thumbnail slot: 96×54, 8pt corner, and *always
/// reserved* when the list can contain thumbnails — an empty slot renders
/// `Surface.control`, so the column's rhythm never goes ragged between a row
/// that has an image and one that doesn't.
struct RowThumbnail: View {
    let url: URL?

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
            .fill(Surface.control)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(.rect(cornerRadius: Radius.thumbnail, style: .continuous))
            .frame(width: Metric.thumbnailSize.width, height: Metric.thumbnailSize.height)
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url else { return }
                image = await ArticleImageCache.shared.image(
                    for: url, targetWidth: Metric.thumbnailSize.width
                )
            }
    }
}

/// The one row component. `Identity` is the leading source mark (a
/// `FaviconTile`, or `EmptyView` for a list whose rows are all one source).
struct ReadableRow<Identity: View>: View {
    /// **R1.** The unread signal is one thing: a 3pt `Accent.primary` leading
    /// rail at inset 0. Not a dot, not a colour change, not both — a read row
    /// drops the rail and shifts the title to `Ink.secondary`.
    let isUnread: Bool
    let title: String
    var summary: String?
    var metadata: RowMetadata
    /// Whether this list can contain thumbnails. When true the slot is
    /// reserved on every row (R4), even the ones with no image.
    var reservesThumbnail = false
    var thumbnailURL: URL?
    @ViewBuilder var identity: () -> Identity

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// **R5.** Row height is fixed per list at three lines minimum: a row with
    /// no summary pads, it does not collapse. Scaled, so it grows with the
    /// text rather than clipping it (T9).
    @ScaledMetric(relativeTo: .body) private var minimumTextHeight: CGFloat = 66

    /// **T9.** Above `.accessibility1` the thumbnail drops out and the row is
    /// all text; metadata is allowed the second line it needs.
    private var isAccessibilitySize: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        HStack(spacing: 0) {
            rail
            HStack(alignment: .top, spacing: 12) {
                identity()
                VStack(alignment: .leading, spacing: 4) {
                    // §4.3 row title: `.body`, semibold unread / regular read,
                    // 2 lines max.
                    Text(title)
                        .font(.body.weight(isUnread ? .semibold : .regular))
                        .foregroundStyle(isUnread ? Ink.primary : Ink.secondary)
                        .lineLimit(2)
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                            .lineSpacing(2)
                            .lineLimit(2)
                    }
                    metaLine
                }
                .frame(maxWidth: .infinity, minHeight: minimumTextHeight, alignment: .topLeading)
                if reservesThumbnail, !isAccessibilitySize {
                    RowThumbnail(url: thumbnailURL)
                }
            }
            .padding(.horizontal, Metric.containerPadding)
            .padding(.vertical, Metric.rowVerticalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text("Unread") : Text("Read"))
    }

    /// **R1.** Full row height, inset 0. Always laid out — the read state
    /// changes its colour, never the row's geometry.
    private var rail: some View {
        Rectangle()
            .fill(isUnread ? Accent.primary : .clear)
            .frame(width: RowRail.width)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var metaLine: some View {
        let text = metadata.text
        if !text.isEmpty {
            HStack(spacing: 4) {
                if metadata.isFailed {
                    Image(systemName: "exclamationmark.triangle")
                        .uiGlyph(size: Font.GlyphSize.caption)
                        .foregroundStyle(Semantic.warning)
                        .accessibilityHidden(true)
                }
                Text(text)
                    // T8/T9 — one line at ordinary sizes; at accessibility
                    // sizes it is allowed to wrap rather than truncate.
                    .lineLimit(isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(Ink.tertiary)
        }
    }
}

/// Geometry shared by the row and the lists that host it: **R1**'s rail must
/// sit at inset 0, so a `pageList()` row's `listRowInsets` are zero and the
/// row owns its own padding.
enum RowRail {
    static let width: CGFloat = 3

    /// A `ReadableRow` measures its own insets, so the list must not add any.
    static let listRowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

extension View {
    /// A `ReadableRow` inside a `pageList()`: zero list insets (the row owns
    /// its padding so R1's rail reaches inset 0) on the E1 container fill.
    func readableRowStyle() -> some View {
        listRowInsets(RowRail.listRowInsets)
            .containerRow()
    }
}
