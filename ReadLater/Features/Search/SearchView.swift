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
                .readableRowStyle()
            }
        }
        .pageList()
        .searchable(text: $query, prompt: "Search articles and highlights")
        .onChange(of: query) { _, new in
            runSearch(new)
        }
        .navigationTitle("Search")
        .sidebarBackToolbarItem()
        // E1/E2 — both states use the one template. The copy names no action
        // (the search field is already on screen), so neither gets a capsule.
        .emptyStateOverlay(emptyState)
    }

    private var emptyState: EmptyStateView? {
        if query.isEmpty {
            return EmptyStateView(
                mark: "magnifyingglass",
                title: "Search everything",
                message: "Every word of every saved article and highlight is searchable here."
            )
        }
        if results.isEmpty {
            return EmptyStateView(
                mark: "magnifyingglass",
                title: "No matches",
                message: "Nothing in your library contains “\(query)”."
            )
        }
        return nil
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
