import Foundation
import SwiftData

/// Writes markdown exports to a user-picked folder (any Files provider — iCloud
/// Drive, Dropbox, local, etc.). Stores a security-scoped bookmark so writes
/// keep working after app relaunch.
@MainActor
final class ObsidianExporter {

    enum ExportError: Error {
        case noDestinationConfigured
        case bookmarkStale
        case couldNotAccessDestination
        case write(Error)
    }

    /// Called by SettingsView when the user picks a folder. Persists a fresh
    /// security-scoped bookmark into AppSettings.
    static func setDestination(_ url: URL, in settings: AppSettings) throws {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        let data = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        settings.obsidianBookmarkData = data
    }

    static func destinationURL(from settings: AppSettings) throws -> URL {
        guard let data = settings.obsidianBookmarkData else {
            throw ExportError.noDestinationConfigured
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale { throw ExportError.bookmarkStale }
        return url
    }

    /// Writes (or overwrites) the article's export file. Because we render
    /// deterministically, this is idempotent.
    static func exportArticle(_ article: Article, settings: AppSettings) throws {
        let destRoot = try destinationURL(from: settings)
        guard destRoot.startAccessingSecurityScopedResource() else {
            throw ExportError.couldNotAccessDestination
        }
        defer { destRoot.stopAccessingSecurityScopedResource() }

        let subfolder = settings.obsidianSubfolder.trimmingCharacters(in: .whitespaces)
        let folder: URL = subfolder.isEmpty
            ? destRoot
            : destRoot.appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let file = folder.appendingPathComponent(MarkdownFormatter.fileName(for: article))
        let contents = MarkdownFormatter.render(.init(article: article, highlights: article.highlights))
        do {
            try contents.write(to: file, atomically: true, encoding: .utf8)
            let now = Date()
            for h in article.highlights where h.exportedAt == nil || h.exportedAt! < h.createdAt {
                h.exportedAt = now
            }
        } catch {
            throw ExportError.write(error)
        }
    }

    /// Writes every article that has at least one highlight. Used for the
    /// "Export all" action in Settings.
    static func exportAll(context: ModelContext, settings: AppSettings) throws {
        let all = try context.fetch(FetchDescriptor<Article>())
        for a in all where !a.highlights.isEmpty {
            try exportArticle(a, settings: settings)
        }
    }
}
