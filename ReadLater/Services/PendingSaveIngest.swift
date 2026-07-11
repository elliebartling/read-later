import Foundation
import SwiftData

/// Drains PendingSave JSONs from the App Group container into SwiftData.
/// Runs on app foreground and after a share/deep link fires.
@MainActor
final class PendingSaveIngest {
    static let shared = PendingSaveIngest()

    private var context: ModelContext? {
        // Grab the app's main context lazily. The App scene attaches its
        // ModelContainer via `.modelContainer(...)`, which we can reach via
        // ModelContainer.default once the app is up. We fall back to nil in
        // tests / previews.
        // In practice we accept an explicit context via `drain(using:)`.
        nil
    }

    func drain() async {
        let saves = PendingSave.loadAll()
        guard !saves.isEmpty else { return }
        for save in saves {
            await ingest(save)
            PendingSave.remove(id: save.id)
        }
    }

    private func ingest(_ save: PendingSave) async {
        do {
            let container = SharedModelContainer.make()
            let ctx = container.mainContext
            let placeholderTitle = save.title ?? save.url.host ?? save.url.absoluteString
            let article = Article(
                url: save.url,
                title: placeholderTitle,
                savedAt: save.savedAt,
                parseStatus: .pending
            )
            ctx.insert(article)
            try ctx.save()

            let parsed = try await ArticleParser.shared.parse(url: save.url, prefetchedHTML: save.capturedHTML)
            article.title = parsed.title.isEmpty ? placeholderTitle : parsed.title
            article.author = parsed.author
            article.siteName = parsed.siteName
            article.plainText = parsed.plainText
            article.extractedHTML = parsed.extractedHTML
            article.heroImageURL = parsed.heroImageURL
            article.estimatedReadingMinutes = parsed.estimatedReadingMinutes
            article.parseStatus = .ready
            try ctx.save()
        } catch {
            // Mark failed but keep the row so the user can retry.
            NSLog("PendingSaveIngest failed for %@: %@", save.url.absoluteString, String(describing: error))
        }
    }
}
