import SwiftUI
import SwiftData

/// Layer 1 — the Search group. The shell owns the `NavigationStack` and the
/// Article destination.
struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var results: [Article] = []

    var body: some View {
        List {
            ForEach(results) { article in
                NavigationLink(value: article) {
                    ArticleRow(article: article)
                }
                .listRowInsets(EdgeInsets(
                    top: Metric.rowVerticalPadding, leading: Metric.containerPadding,
                    bottom: Metric.rowVerticalPadding, trailing: Metric.containerPadding
                ))
                .containerRow()
            }
        }
        .pageList()
        .searchable(text: $query, prompt: "Search articles and highlights")
        .onChange(of: query) { _, new in
            runSearch(new)
        }
        .navigationTitle("Search")
        .sidebarBackToolbarItem()
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass",
                                       description: Text("Full-text search across saved articles."))
            } else if results.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private func runSearch(_ q: String) {
        guard !q.isEmpty else { results = []; return }
        let lower = q.lowercased()
        var descriptor = FetchDescriptor<Article>()
        // SwiftData #Predicate can't yet call String.lowercased on stored
        // properties in Xcode 15, so we do a broad fetch + in-memory filter.
        // This is the flagged "upgrade to FTS5 if perf sags" path in the plan.
        descriptor.fetchLimit = 500
        let all = (try? context.fetch(descriptor)) ?? []
        results = all.filter {
            $0.title.lowercased().contains(lower)
            || $0.plainText.lowercased().contains(lower)
            || ($0.author ?? "").lowercased().contains(lower)
        }
    }
}
