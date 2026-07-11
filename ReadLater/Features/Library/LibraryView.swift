import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if articles.isEmpty {
                    ContentUnavailableView(
                        "No articles yet",
                        systemImage: "books.vertical",
                        description: Text("Share links from Safari, or tap + to paste one.")
                    )
                    .listRowSeparator(.hidden)
                }
                ForEach(articles) { article in
                    ZStack {
                        NavigationLink(value: article) { EmptyView() }.opacity(0)
                        ArticleRow(article: article)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
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
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
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
