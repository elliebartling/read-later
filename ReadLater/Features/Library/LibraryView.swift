import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var path = NavigationPath()

    private var filtered: [Article] {
        guard !searchText.isEmpty else { return articles }
        let q = searchText.lowercased()
        return articles.filter {
            $0.title.lowercased().contains(q) || ($0.author ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ScrollDetectorRow()
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No articles yet",
                        systemImage: "books.vertical",
                        description: Text("Share links from Safari, or tap + to paste one.")
                    )
                    .listRowSeparator(.hidden)
                }
                ForEach(filtered) { article in
                    NavigationLink(value: article) {
                        ArticleRow(article: article)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(article) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            article.isArchived.toggle()
                        } label: {
                            Label(article.isArchived ? "Unarchive" : "Archive",
                                  systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Article.self) { article in
                ReaderView(article: article)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddArticleSheet()
            }
            .hidesTabBarOnScrollDown()
        }
        .task(id: appModel.pendingArticleToOpen) {
            await handlePendingOpen()
        }
    }

    private func handlePendingOpen() async {
        guard let id = appModel.pendingArticleToOpen else { return }
        // Poll briefly — the deep link handler drains PendingSaves before
        // setting this ID, but SwiftData's fetch may take a beat to surface
        // the freshly-inserted row.
        for _ in 0..<40 {
            if let target = fetchArticle(id: id) {
                if path.count > 0 { path.removeLast(path.count) }
                path.append(target)
                appModel.pendingArticleToOpen = nil
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        appModel.pendingArticleToOpen = nil
    }

    private func fetchArticle(id: UUID) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func delete(_ article: Article) {
        context.delete(article)
        try? context.save()
    }
}

struct AddArticleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://example.com/article", text: $urlString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .navigationTitle("Add URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let url = URL(string: urlString) {
                            let pending = PendingSave(url: url, source: .manual)
                            try? pending.write()
                            Task { await PendingSaveIngest.drain(context: context) }
                            dismiss()
                        }
                    }
                    .disabled(URL(string: urlString) == nil)
                }
            }
        }
    }
}
