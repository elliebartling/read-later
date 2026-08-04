import SwiftUI
import SwiftData

/// The Highlights destination, rebuilt in wave 3 (§8.4 H2/H3, §8.1 R6).
///
/// The audit called this the weakest full surface in the app, for three
/// reasons this view now answers:
///
///  - **H3** highlights group by article, one header per article. Two
///    highlights from one post used to print its full title twice.
///  - **H2** the colour is a 4pt full-height leading rail in the *marker*
///    colour, not an 8pt pastel dot, and the quote leads: content first,
///    source metadata beneath at `.caption` / `Ink.tertiary`. The hierarchy
///    used to be inverted, with the article title at full width above the
///    quote at similar weight.
///  - **R6** every row is a real `NavigationLink` that lands on the passage.
///    Revisiting a highlight in its context is the core loop of a
///    Readwise-style app and it simply did not exist.
struct HighlightsView: View {
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]

    private var groups: [HighlightGrouping.Group] {
        HighlightGrouping.group(highlights)
    }

    var body: some View {
        NavigationStack {
            List {
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "No highlights yet",
                        systemImage: "highlighter",
                        description: Text("Select text in the reader to highlight.")
                    )
                    .listRowSeparator(.hidden)
                    .containerRow()
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.highlights) { highlight in
                            row(for: highlight)
                        }
                    } header: {
                        // §4.3 section header: sentence case, never all-caps.
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.secondary)
                            .textCase(nil)
                            .lineLimit(2)
                    }
                }
            }
            .pageList()
            .navigationTitle("Highlights")
            .navigationDestination(for: HighlightPassage.self) { passage in
                ReaderView(article: passage.article, scrollToOffset: passage.offset)
            }
        }
    }

    @ViewBuilder
    private func row(for highlight: Highlight) -> some View {
        if let article = highlight.article {
            NavigationLink(
                value: HighlightPassage(article: article, offset: highlight.startOffset)
            ) {
                HighlightRow(highlight: highlight)
            }
            .listRowInsets(rowInsets)
            .containerRow()
        } else {
            // Orphaned by a deleted article — still worth showing, but there
            // is no passage to land on, so it is deliberately not a link (R6
            // is about rows that *can* navigate).
            HighlightRow(highlight: highlight)
                .listRowInsets(rowInsets)
                .containerRow()
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: Metric.rowVerticalPadding, leading: Metric.containerPadding,
            bottom: Metric.rowVerticalPadding, trailing: Metric.containerPadding
        )
    }
}

/// The navigation value for "open this article at this highlight". A struct
/// rather than the `Highlight` itself so the destination reads as what it is:
/// an article plus a place in it.
struct HighlightPassage: Hashable {
    let article: Article
    /// UTF-16 offset into `article.plainText` — the same offset space the
    /// readers restore reading position in.
    let offset: Int
}

/// **H2.** Quote leads; the marker colour is a full-height leading rail.
private struct HighlightRow: View {
    let highlight: Highlight

    /// H2 — 4pt, full row height.
    private static let railWidth: CGFloat = 4

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: Self.railWidth / 2, style: .continuous)
                .fill(highlight.color.marker)
                .frame(width: Self.railWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.quotedText)
                    .font(.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(6)
                if let note = highlight.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(4)
                }
                // R2 — one `.caption` line, `Ink.tertiary`, `" · "` joined, no
                // glyphs. The article title is the section header (H3), so it
                // is dropped here rather than repeated.
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(highlight.color.displayName) highlight. \(highlight.quotedText)"
        )
    }

    private var metadata: String {
        var fields = [highlight.createdAt.formatted(.relative(presentation: .named))]
        if highlight.exportedAt != nil { fields.append("Exported") }
        return fields.joined(separator: " · ")
    }
}
