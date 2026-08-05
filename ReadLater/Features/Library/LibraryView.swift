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
                        .uiGlyph(size: Font.GlyphSize.subheadline)
                        .foregroundStyle(Semantic.warning)
                }
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .listRowSeparator(.hidden)
                .containerRow()
            }
            ForEach(articles) { article in
                // **R6.** A real `NavigationLink` with the system disclosure.
                // This used to be a `NavigationLink` hidden at `opacity(0)`
                // behind the row in a `ZStack`, so Library rows had no chevron
                // while the same `ArticleRow` in Search did.
                NavigationLink(value: article) {
                    ArticleRow(article: article)
                }
                .readableRowStyle()
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
        // **E1.** The empty state is an overlay centred in the viewport, never
        // a list row — it used to sit high under the title while Search's
        // equivalent was correctly centred.
        .emptyStateOverlay(articles.isEmpty ? emptyState : nil)
        .navigationTitle("Library")
        // Leading slot is the back-to-sidebar affordance now; the Settings
        // gear that used to live here moved into the sidebar (#57).
        .sidebarBackToolbarItem()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddSheet = true } label: {
                    // I2/I4 — one weight, one scale, monochrome.
                    Image(systemName: "plus").uiGlyph()
                }
                .accessibilityLabel("Add link")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddArticleSheet()
        }
    }

    /// **E2.** One sentence naming the mechanism, and the action the copy
    /// names rendered as the screen's one prominent capsule.
    private var emptyState: EmptyStateView {
        EmptyStateView(
            mark: "books.vertical",
            title: "Nothing saved yet",
            message: "Share a link from Safari, or paste one here, and it lands in your library ready to read.",
            actionTitle: "Add a link",
            action: { showingAddSheet = true }
        )
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
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // SH3 — verb + object. "Save" alone was the bare verb the
                    // constitution calls out beside Add feed's bare "Subscribe".
                    Button("Save link") {
                        if let url = URL(string: urlString) {
                            let pending = PendingSave(url: url, source: .manual)
                            try? pending.write()
                            // §9's save moment: the one haptic M4 allows here.
                            Haptic.success()
                            Task { await PendingSaveIngest.drain(context: context) }
                            dismiss()
                        }
                    }
                    .disabled(URL(string: urlString) == nil)
                }
            }
        }
        // §8.2 — a **Form** sheet. One field never gets a full screen.
        .presentationDetents([.height(Metric.formSheetHeight)])
    }
}
