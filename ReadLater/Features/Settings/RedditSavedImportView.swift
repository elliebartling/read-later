import SwiftData
import SwiftUI

/// Imports the signed-in user's Reddit saved posts into the library. Framed as
/// getting that history *out of Reddit* and into a durable, highlightable,
/// exportable collection. Fetches saved posts (paginated, capped), dedupes
/// against existing articles, and writes them through the normal ingest
/// pipeline; parsing continues in the background off the shared serial parse
/// chain, so this screen returns as soon as the stubs are queued.
struct RedditSavedImportView: View {
    @Environment(\.modelContext) private var context
    @State private var model = RedditSavedImportModel()

    var body: some View {
        Form {
            switch model.phase {
            case .idle:
                idleSection
            case .fetching:
                fetchingSection
            case .importing:
                Section {
                    HStack {
                        ProgressView()
                        Text("Adding to your library…")
                    }
                }
            case .done(let result):
                doneSection(result)
            case .failed(let message):
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Try Again") { start() }
                }
            }
        }
        .navigationTitle("Import Saved Posts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var idleSection: some View {
        Section {
            Button {
                start()
            } label: {
                Label("Import My Saved Posts", systemImage: "square.and.arrow.down")
            }
        } footer: {
            Text("Brings up to \(RedditImporter.defaultSavedImportCap) of your most recent Reddit saved posts into your library. Link posts import the linked article; text posts import the post body. Comments are skipped. Already-saved links are not duplicated.")
        }
    }

    private var fetchingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text(model.fetchedCount == 0
                    ? "Fetching your saved posts…"
                    : "Fetched \(model.fetchedCount) post\(model.fetchedCount == 1 ? "" : "s")…")
            }
        }
    }

    private func doneSection(_ result: RedditImporter.SavedImportResult) -> some View {
        Section {
            Label("Imported \(result.imported) post\(result.imported == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if result.skipped > 0 {
                Text("\(result.skipped) already in your library or had no link — skipped.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("New posts appear in your Library now and finish extracting in the background. Open any that are still loading to prioritize them.")
        }
    }

    private func start() {
        Task { await model.run(context: context) }
    }
}

@MainActor
@Observable
final class RedditSavedImportModel {
    enum Phase: Equatable {
        case idle
        case fetching
        case importing
        case done(RedditImporter.SavedImportResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var fetchedCount = 0

    private let reddit: RedditAuthController

    init(reddit: RedditAuthController = .shared) {
        self.reddit = reddit
    }

    func run(context: ModelContext) async {
        guard let account = reddit.account else {
            phase = .failed(RedditAuthError.notSignedIn.localizedDescription)
            return
        }
        phase = .fetching
        fetchedCount = 0
        do {
            let posts = try await reddit.client.savedPosts(
                username: account.name,
                maxPosts: RedditImporter.defaultSavedImportCap,
                onProgress: { [weak self] count in
                    Task { @MainActor in self?.fetchedCount = count }
                }
            )
            phase = .importing
            let result = await RedditImporter.importSaved(posts, context: context)
            phase = .done(result)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }
}
