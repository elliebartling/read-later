import Foundation
import SwiftData

/// Drains PendingSave JSONs from the App Group container into SwiftData.
///
/// Two-phase design:
/// 1. **Insert stub** — synchronously insert an `Article` for each pending save,
///    reusing the pending save's UUID as the article's UUID so a share-sheet
///    deep link like `readlater://open?id=<uuid>` resolves immediately.
/// 2. **Parse** — kick off background Tasks that run `ArticleParser` and fill
///    in `plainText`, `title`, etc. once the WKWebView finishes.
///
/// Callers `await drain(context:)` and by the time it returns, phase 1 is
/// complete and the deep link can push a `ReaderView` — even if phase 2 hasn't
/// finished yet (ReaderView shows a loading state on `parseStatus == .pending`).
@MainActor
enum PendingSaveIngest {

    /// Serial chain so overlapping drain() calls (e.g. `.task` + `.onOpenURL`
    /// firing on cold start) don't double-process the same file.
    private static var chain: Task<Void, Never>?

    /// Parses are serialized too because ArticleParser's WKWebView is single-slot.
    private static var parseChain: Task<Void, Never>?

    static func drain(context: ModelContext) async {
        let prior = chain
        let mine = Task { @MainActor in
            _ = await prior?.value
            await doDrain(context: context)
        }
        chain = mine
        _ = await mine.value
    }

    private static func doDrain(context: ModelContext) async {
        let saves = PendingSave.loadAll()
        guard !saves.isEmpty else { return }

        var toParse: [(UUID, String?)] = []
        for save in saves {
            let id = save.id
            var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let existing = (try? context.fetch(descriptor)) ?? []
            if !existing.isEmpty {
                PendingSave.remove(id: save.id)
                continue
            }
            let article = Article(
                id: save.id,
                url: save.url,
                title: save.title ?? save.url.host ?? save.url.absoluteString,
                savedAt: save.savedAt,
                parseStatus: .pending
            )
            context.insert(article)
            toParse.append((save.id, save.capturedHTML))
            PendingSave.remove(id: save.id)
        }
        try? context.save()

        for (id, html) in toParse {
            let prior = parseChain
            parseChain = Task { @MainActor in
                _ = await prior?.value
                await parseOne(id: id, context: context, prefetchedHTML: html)
            }
        }
    }

    private static func parseOne(id: UUID, context: ModelContext, prefetchedHTML: String?) async {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let article = try? context.fetch(descriptor).first else { return }
        guard let url = article.url else {
            article.parseStatus = .failed
            try? context.save()
            return
        }
        do {
            let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: prefetchedHTML)
            article.apply(parsed, updateTitle: true)
            article.parseStatus = .ready
            try context.save()
        } catch {
            NSLog("PendingSaveIngest parse failed for %@: %@",
                  url.absoluteString, String(describing: error))
            article.parseStatus = .failed
            try? context.save()
        }
    }
}
