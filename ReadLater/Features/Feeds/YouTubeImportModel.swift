import Foundation
import SwiftData

/// Drives the one-time YouTube subscription import flow (`YouTubeImportView`):
/// holds the harvested/parsed channel list, tracks which are already subscribed,
/// manages the checkbox selection, and subscribes the chosen channels by
/// creating RSS feeds through the wave-1 machinery.
///
/// The two data sources (logged-in DOM harvest, Takeout CSV) both funnel into
/// `present(channels:)`, which splits them into *new* vs *already-subscribed*
/// against the current `Feed` set. Only new channels are selectable; already
/// subscribed ones are surfaced as a count so the user sees they were skipped
/// (dedupe requirement) rather than silently dropped.
@MainActor
@Observable
final class YouTubeImportModel {

    /// Where the flow is. `.failure` always carries actionable text pointing at
    /// the CSV fallback — there is no state that leaves the user on a spinner.
    enum Phase: Equatable {
        case chooseSource
        case harvesting
        case picking
        case subscribing
        case done(added: Int)
        case failure(String)
    }

    private(set) var phase: Phase = .chooseSource

    /// New (not-yet-subscribed) channels, in source order — the picker rows.
    private(set) var newChannels: [ImportableChannel] = []
    /// Count of harvested/parsed channels already in the user's feeds (skipped).
    private(set) var alreadySubscribedCount = 0
    /// Selected channel ids (`ImportableChannel.id`). None pre-checked.
    private(set) var selection = Set<String>()
    /// Non-fatal per-channel failures during the last subscribe, for a footer.
    private(set) var failedCount = 0

    var allSelected: Bool { !newChannels.isEmpty && selection.count == newChannels.count }
    var canSubscribe: Bool { !selection.isEmpty }

    /// Returns to the source chooser, clearing any harvested/parsed state — used
    /// by the failure screen's "Back" action.
    func reset() {
        newChannels = []
        alreadySubscribedCount = 0
        selection = []
        failedCount = 0
        phase = .chooseSource
    }

    // MARK: - Source entry points

    /// Runs the logged-in `feed/channels` harvest and presents the result. Called
    /// after the `SiteLoginView` sheet dismisses. Any harvest failure lands in
    /// `.failure` with guidance toward the CSV path.
    func runHarvest(existingChannelIDs: Set<String>) async {
        phase = .harvesting
        do {
            let channels = try await YouTubeSubscriptionHarvester().harvest()
            present(channels: channels, existingChannelIDs: existingChannelIDs)
        } catch {
            phase = .failure((error as? LocalizedError)?.errorDescription
                ?? "Couldn't read your subscriptions. Try importing from a Google Takeout file instead.")
        }
    }

    /// Parses a Takeout `subscriptions.csv` at `url` (a security-scoped file from
    /// `.fileImporter`) and presents the result.
    func importCSV(from url: URL, existingChannelIDs: Set<String>) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let channels = YouTubeSubscriptionImport.channels(fromCSV: text)
            if channels.isEmpty {
                phase = .failure("No channels found in that file. Pick the subscriptions.csv from your Google Takeout export (Takeout ▸ YouTube ▸ subscriptions).")
                return
            }
            present(channels: channels, existingChannelIDs: existingChannelIDs)
        } catch {
            phase = .failure("Couldn't read that file. Pick the subscriptions.csv from your Google Takeout export.")
        }
    }

    /// Splits `channels` into new vs already-subscribed and moves to the picker.
    /// Pure enough to unit-test: no WebKit, no network.
    func present(channels: [ImportableChannel], existingChannelIDs: Set<String>) {
        var newOnes: [ImportableChannel] = []
        var already = 0
        for channel in channels {
            if let id = channel.channelID, existingChannelIDs.contains(id) {
                already += 1
            } else {
                newOnes.append(channel)
            }
        }
        newChannels = newOnes
        alreadySubscribedCount = already
        selection = []
        phase = .picking
    }

    // MARK: - Selection

    func isSelected(_ channel: ImportableChannel) -> Bool { selection.contains(channel.id) }

    func toggle(_ channel: ImportableChannel) {
        if selection.contains(channel.id) {
            selection.remove(channel.id)
        } else {
            selection.insert(channel.id)
        }
    }

    func selectAll() { selection = Set(newChannels.map(\.id)) }
    func deselectAll() { selection = [] }

    // MARK: - Subscribe

    /// Subscribes every selected channel by resolving its Atom feed URL and
    /// creating a `Feed` seeded with the fetched entries — the same path
    /// `AddFeedSheet` uses, batched. Channels whose id is already known skip
    /// resolution; handle-only channels resolve via wave-1
    /// `YouTubeChannel.resolveFeedURL`. Duplicates (by resolved feed URL) and
    /// per-channel failures are skipped without aborting the batch.
    func subscribeSelected(context: ModelContext) async {
        let chosen = newChannels.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        phase = .subscribing
        failedCount = 0

        // Snapshot already-subscribed feed URLs so we don't double-insert within
        // this batch or against pre-existing feeds.
        var existingFeedURLs = Set<URL>()
        for feed in (try? context.fetch(FetchDescriptor<Feed>())) ?? [] {
            if let url = feed.feedURL { existingFeedURLs.insert(url) }
        }

        var added = 0
        for channel in chosen {
            do {
                guard let feedURL = try await resolveFeedURL(for: channel) else { failedCount += 1; continue }
                if existingFeedURLs.contains(feedURL) { continue }
                let parsed = try await FeedFetcher.fetch(feedURL: feedURL)
                let feed = Feed(
                    feedURL: feedURL,
                    siteURL: parsed.siteURL,
                    title: parsed.title.isEmpty ? channel.title : parsed.title
                )
                context.insert(feed)
                FeedRefresher.merge(parsed: parsed, into: feed, context: context)
                existingFeedURLs.insert(feedURL)
                added += 1
            } catch {
                failedCount += 1
            }
        }
        try? context.save()
        phase = .done(added: added)
    }

    /// Resolves a channel's feed URL: no network when the `UC…` id is known,
    /// otherwise the wave-1 handle resolver.
    private func resolveFeedURL(for channel: ImportableChannel) async throws -> URL? {
        if let direct = channel.directFeedURL { return direct }
        return try await YouTubeChannel.resolveFeedURL(from: channel.reference)
    }

    // MARK: - Helpers

    /// The `UC…` ids of the user's existing YouTube channel feeds, for dedupe.
    /// A YouTube channel feed URL is `…/feeds/videos.xml?channel_id=UC…`.
    static func existingChannelIDs(in feeds: [Feed]) -> Set<String> {
        var ids = Set<String>()
        for feed in feeds {
            guard let url = feed.feedURL,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let id = components.queryItems?.first(where: { $0.name == "channel_id" })?.value,
                  YouTubeChannel.isValidChannelID(id)
            else { continue }
            ids.insert(id)
        }
        return ids
    }
}
