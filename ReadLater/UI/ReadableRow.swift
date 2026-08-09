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
//     [ title (2 lines max) ]                              [thumbnail]
//     [ summary (2 lines, optional) ]                       [ 96×54 ]
//     [ meta · meta · meta ]
//
// Library, All Items, per-feed lists and Search all render this. The source
// identity mark (BR1/BR2, wave 3) rides in the `identity` slot, ahead of the
// text column.

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
        [elasticText, fixedText].filter { !$0.isEmpty }.joined(separator: Self.separator)
    }

    /// The **elastic** half of the line: the fields whose length nobody
    /// controls. A site name can be two characters or forty, and a relative
    /// date grows from "now" to "last month". These are the fields that give
    /// way when the row runs out of width.
    var elasticText: String {
        var fields: [String] = []
        if isFailed { fields.append("Couldn't parse") }
        if let source, !source.isEmpty { fields.append(source) }
        if let date { fields.append(date.formatted(.relative(presentation: .named))) }
        return fields.joined(separator: Self.separator)
    }

    /// The **fixed** half: short, bounded, self-describing states and counts —
    /// "33 min", "Video", "2 highlights". They are last in R2's field order and
    /// they are the fields a reader is actually scanning for, so they render at
    /// full length and the elastic half truncates around them.
    var fixedText: String {
        details.filter { !$0.isEmpty }.joined(separator: Self.separator)
    }

    /// **R2.** The one legal joiner. Spelled once so a call site cannot invent
    /// a second one.
    static let separator = " · "
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
    /// **R1 (amended, Ellen's review of PR #73).** The unread signal is *no
    /// added chrome at all*. An unread row is simply the row at full ink; a
    /// read row recedes — title to `Ink.secondary` at regular weight, thumbnail
    /// faded. The original R1 drew a 3pt `Accent.primary` leading rail at inset
    /// 0; in an all-unread list the per-row rails merged into one bar hugging
    /// the container card's rounded left edge, and a one-sided border on a
    /// rounded card is never right. It also had no job the title tone was not
    /// already doing. Deleted rather than thinned.
    ///
    /// (The Highlights passage rail is a different thing and stays: it is
    /// *inside* its card and it carries the marker colour, which no other
    /// element encodes.)
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
        HStack(alignment: .top, spacing: 12) {
            identity()
            VStack(alignment: .leading, spacing: 4) {
                // §4.3 row title: `.body`, semibold unread / regular read,
                // 2 lines max. R1 (amended) — this tone shift *is* the read
                // signal; nothing else marks it.
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
                    // R1 (amended) — a read row recedes as a whole, image
                    // included. Opacity, not a second colour.
                    .opacity(isUnread ? 1 : RowLayout.readThumbnailOpacity)
            }
        }
        .padding(.horizontal, Metric.containerPadding)
        .padding(.vertical, Metric.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text("Unread") : Text("Read"))
    }

    /// **R2 / T8.** One `.caption` line, `Ink.tertiary`, fields joined by
    /// `" · "` — but rendered as two runs, not one string.
    ///
    /// **The build-44 defect this fixes.** As one `Text` with `.lineLimit(1)`
    /// and tail truncation, the line lost its *last* field first — which is the
    /// field order's most informative slot (R2 puts state and counts last). In
    /// All Items a saved entry read `AskHistorians · 2 hours a…`: the state was
    /// on screen in the string and off screen in the pixels. At Dynamic Type
    /// sizes where the line was allowed a second row it did the other bad
    /// thing and broke a short word across it — the "Save"/"d" break T8 was
    /// written for, resurrected by wrapping instead of by an `HStack`.
    ///
    /// So the two halves get different rules. `elasticText` (source, date) is
    /// the part nobody controls the length of: one line, tail truncation, no
    /// layout priority — it gives way. `fixedText` (durations, counts, kinds)
    /// is short and bounded: `.fixedSize` so it can never wrap **or** break
    /// mid-word, and the layout priority to claim its width first. A row too
    /// narrow for both loses site name characters, never a whole field and
    /// never half a word.
    @ViewBuilder
    private var metaLine: some View {
        let elastic = metadata.elasticText
        let fixed = metadata.fixedText
        if !elastic.isEmpty || !fixed.isEmpty {
            HStack(spacing: 4) {
                if metadata.isFailed {
                    Image(.warning)
                        .uiGlyph(size: Font.GlyphSize.caption)
                        .foregroundStyle(Semantic.warning)
                        .accessibilityHidden(true)
                }
                // Spacing 0: the joiner carries its own spaces, so the two runs
                // butt together and read as one line.
                HStack(spacing: 0) {
                    if !elastic.isEmpty {
                        Text(elastic)
                            // T8/T9 — one line at ordinary sizes; at
                            // accessibility sizes it may take a second line
                            // rather than truncate.
                            .lineLimit(isAccessibilitySize ? 2 : 1)
                            .truncationMode(.tail)
                            .layoutPriority(0)
                    }
                    if !fixed.isEmpty {
                        // The joiner rides the FIXED run, not the elastic one.
                        // Trailing it on the elastic run puts it inside the
                        // truncated region, so a squeezed row rendered
                        // `reddit.com · 13 min… 1 min` with the " · " eaten.
                        Text(elastic.isEmpty ? fixed : RowMetadata.separator + fixed)
                            .lineLimit(1)
                            // T8 — a bounded field never wraps and never breaks
                            // mid-word, at any width or type size.
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Ink.tertiary)
            // The two runs are one sentence to VoiceOver, whatever the layout
            // did to them.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metadata.text)
        }
    }
}

/// Geometry shared by the row and the lists that host it: the row measures its
/// own padding (`Metric.containerPadding`), so the list must not add a second
/// set on top of it.
enum RowLayout {
    /// A `ReadableRow` measures its own insets, so the list must not add any.
    static let listRowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    /// **R1 (amended).** How far a read row's thumbnail recedes. Enough to
    /// read as "done", not so far that the image becomes a smudge.
    static let readThumbnailOpacity: Double = 0.7
}

extension View {
    /// A `ReadableRow` inside a `pageList()`: zero list insets (the row owns
    /// its padding) on the E1 container fill.
    func readableRowStyle() -> some View {
        listRowInsets(RowLayout.listRowInsets)
            .containerRow()
    }
}
