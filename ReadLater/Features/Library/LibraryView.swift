import SwiftUI
import SwiftData

/// Layer 1 — the Library group. The shell owns the `NavigationStack` and the
/// Article destination; this view is only ever its root.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    @State private var showingAddSheet = false

    var body: some View {
        List {
            if !AppGroup.hasSharedContainer {
                // E3 — a failure state, so the glyph is `Semantic.warning`.
                // The prose stays `Ink.secondary`: the colour marks the
                // condition, it does not tint a paragraph (N3).
                Label {
                    Text("Sharing is unavailable: the App Group isn't active for Read Later, so links shared from Safari can't reach the app. Enable the App Groups capability (group.com.ellenbartling.readlater) on the app target.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Semantic.warning)
                }
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .listRowSeparator(.hidden)
                .containerRow()
            }
            if articles.isEmpty {
                ContentUnavailableView(
                    "No articles yet",
                    systemImage: "books.vertical",
                    description: Text("Share links from Safari, or tap + to paste one.")
                )
                .listRowSeparator(.hidden)
                .containerRow()
            }
            ForEach(articles) { article in
                ZStack {
                    NavigationLink(value: article) { EmptyView() }.opacity(0)
                    ArticleRow(article: article)
                }
                .listRowInsets(EdgeInsets(
                    top: Metric.rowVerticalPadding, leading: Metric.containerPadding,
                    bottom: Metric.rowVerticalPadding, trailing: Metric.containerPadding
                ))
                .containerRow()
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(article) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    // No tint: the audit found archive wearing an ad-hoc
                    // orange that answers no question (N3). The system's
                    // neutral swipe fill is the right weight.
                    Button {
                        article.isArchived.toggle()
                    } label: {
                        Label(article.isArchived ? "Unarchive" : "Archive",
                              systemImage: "archivebox")
                    }
                }
            }
        }
        .pageList()
        .navigationTitle("Library")
        // Leading slot is the back-to-sidebar affordance now; the Settings
        // gear that used to live here moved into the sidebar (#57).
        .sidebarBackToolbarItem()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                        .imageScale(.medium)
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Add link")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddArticleSheet()
        }
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
            .pageForm()
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
