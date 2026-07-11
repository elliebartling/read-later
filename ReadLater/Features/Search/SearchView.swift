import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var results: [Article] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { article in
                    NavigationLink(value: article) {
                        ArticleRow(article: article)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search articles and highlights")
            .onChange(of: query) { _, new in
                runSearch(new)
            }
            .navigationTitle("Search")
            .navigationDestination(for: Article.self) { article in
                ReaderView(article: article)
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search", systemImage: "magnifyingglass",
                                           description: Text("Full-text search across saved articles."))
                } else if results.isEmpty {
                    ContentUnavailableView.search
                }
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
