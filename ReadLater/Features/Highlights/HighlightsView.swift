import SwiftUI
import SwiftData

/// Layer 1 — the Highlights group. The shell owns the `NavigationStack`.
struct HighlightsView: View {
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]

    var body: some View {
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
            ForEach(highlights) { h in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(h.color.swiftUIColor).frame(width: 8, height: 8)
                        Text(h.article?.title ?? "Unknown")
                            .font(.caption)
                            .foregroundStyle(Ink.tertiary)
                        Spacer()
                        if h.exportedAt != nil {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.caption2)
                                .foregroundStyle(Ink.quaternary)
                        }
                    }
                    Text(h.quotedText)
                        .font(.callout)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(6)
                    if let note = h.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Ink.secondary)
                            .padding(.top, 4)
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: Metric.rowVerticalPadding, leading: Metric.containerPadding,
                    bottom: Metric.rowVerticalPadding, trailing: Metric.containerPadding
                ))
                .containerRow()
            }
        }
        .pageList()
        .navigationTitle("Highlights")
        .sidebarBackToolbarItem()
    }
}
