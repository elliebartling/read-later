import Foundation

/// **H3.** The Highlights destination groups by article, one header per
/// article — before wave 3 two highlights from one post printed the full
/// article title twice, at the top of each row, ahead of the quote (audit:
/// "the weakest full surface in the app").
///
/// Pure so the ordering rules are unit-testable without SwiftData.
enum HighlightGrouping {

    struct Group: Identifiable {
        /// The owning article's ID, or nil for the orphan group (a highlight
        /// whose article was deleted out from under it — CloudKit relationships
        /// are optional, so this is reachable).
        let articleID: UUID?
        let title: String
        let highlights: [Highlight]

        var id: String { articleID?.uuidString ?? "orphans" }
    }

    /// Fallback title for a highlight with no article.
    static let orphanTitle = "Unknown article"

    /// Groups `highlights` by owning article.
    ///
    /// Ordering is inherited, not recomputed: `highlights` arrives newest-first
    /// from the `@Query`, groups appear in the order their newest highlight
    /// does, and within a group the highlights keep the incoming order. So the
    /// article you just annotated is at the top, and re-annotating an old
    /// article floats it back up.
    static func group(_ highlights: [Highlight]) -> [Group] {
        var order: [UUID?] = []
        var buckets: [UUID?: [Highlight]] = [:]
        var titles: [UUID?: String] = [:]

        for highlight in highlights {
            let key = highlight.article?.id
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
                titles[key] = title(for: highlight)
            }
            buckets[key]?.append(highlight)
        }

        return order.map { key in
            Group(
                articleID: key,
                title: titles[key] ?? orphanTitle,
                highlights: buckets[key] ?? []
            )
        }
    }

    private static func title(for highlight: Highlight) -> String {
        guard let article = highlight.article else { return orphanTitle }
        let trimmed = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = article.url?.host { return SourceIdentity.strippingWWW(host) }
        return orphanTitle
    }
}
