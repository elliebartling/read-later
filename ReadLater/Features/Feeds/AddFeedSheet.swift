import SwiftData
import SwiftUI

/// Subscribe to a feed. Presented from the sidebar header (the Feeds tab it
/// used to live in was retired with the tab bar in wave 4).
struct AddFeedSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://example.com or feed URL", text: $urlString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(isResolving)
                    .submitLabel(.go)
                    .onSubmit {
                        guard !isResolving, canSubscribe else { return }
                        Task { await subscribe() }
                    }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Semantic.destructive)
                }
            }
            .pageForm()
            // T7 — sentence case.
            .navigationTitle("Add feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isResolving {
                        ProgressView()
                    } else {
                        // SH3 — verb + object. The constitution names this
                        // exact button: "never a bare 'Subscribe' when the
                        // sibling sheet says 'Save'".
                        Button("Add feed") {
                            Task { await subscribe() }
                        }
                        .disabled(!canSubscribe)
                    }
                }
            }
        }
        // §8.2 — a **Form** sheet. It presented `.large` (the SwiftUI default)
        // for a single URL field, which is the "three heights" the section was
        // written to end.
        .presentationDetents([.height(Metric.formSheetHeight)])
    }

    /// Accepts bare domains ("daringfireball.net") by defaulting to https, and
    /// the Reddit `r/name` shorthand (→ the subreddit's Atom feed). Sort
    /// variants and full URLs pass through literally.
    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let subreddit = RedditFeed.normalizeSubredditShorthand(trimmed) {
            return subreddit
        }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    /// The Subscribe button is enabled for a normal URL/shorthand OR a YouTube
    /// channel reference (a `@handle` has no dot/scheme, so `normalizedURL`
    /// alone wouldn't recognise it).
    private var canSubscribe: Bool {
        normalizedURL != nil || YouTubeChannel.reference(from: urlString) != nil
    }

    private func subscribe() async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            // YouTube channel URLs / @handles resolve to the channel's Atom feed
            // (videos.xml?channel_id=…) before the normal feed resolver runs.
            // Returns nil for non-channel input, which falls through untouched.
            let channelFeedURL = try await YouTubeChannel.resolveFeedURL(from: urlString)
            guard let url = channelFeedURL ?? normalizedURL else { return }
            let resolved = try await FeedFetcher.resolve(url: url)

            let existing = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
            if existing.contains(where: { $0.feedURL == resolved.feedURL }) {
                errorMessage = "You're already subscribed to this feed."
                return
            }

            let feed = Feed(
                feedURL: resolved.feedURL,
                siteURL: resolved.parsed.siteURL,
                title: resolved.parsed.title
            )
            context.insert(feed)
            // Seed entries from the document we already fetched, so the feed
            // has content the moment the sheet closes.
            FeedRefresher.merge(parsed: resolved.parsed, into: feed, context: context)
            try? context.save()
            // M4 — `.success` on save, and this is a save.
            Haptic.success()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't reach that URL."
        }
    }
}
