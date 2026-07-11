import SwiftUI
import SwiftData

struct HighlightsView: View {
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]

    var body: some View {
        NavigationStack {
            List {
                ScrollDetectorRow()
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "No highlights yet",
                        systemImage: "highlighter",
                        description: Text("Select text in the reader to highlight.")
                    )
                }
                ForEach(highlights) { h in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(h.color.swiftUIColor).frame(width: 8, height: 8)
                            Text(h.article?.title ?? "Unknown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if h.exportedAt != nil {
                                Image(systemName: "arrow.up.doc.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(h.quotedText)
                            .font(.callout)
                            .lineLimit(6)
                        if let note = h.note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Highlights")
            .hidesTabBarOnScrollDown()
        }
    }
}
