import SwiftData
import SwiftUI

/// Picker for importing subscribed subreddits as RSS feeds. Loads the signed-in
/// user's subscriptions, presents them as a checklist with **none pre-checked**
/// (a Select All button opts into the whole set), and subscribes the chosen ones
/// via the wave-1 `Feed` machinery (`RedditImporter.subscribe`).
struct RedditSubredditPickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = RedditSubredditPickerModel()

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading subreddits…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.loadError {
                EmptyStateView(
                    mark: .warning,
                    title: "Couldn't load subreddits",
                    message: error,
                    isFailure: true,
                    actionTitle: "Retry",
                    action: { Task { await model.load() } }
                )
                .pageBackground()
            } else if model.subreddits.isEmpty {
                EmptyStateView(
                    mark: .stream,
                    title: "No subreddits",
                    message: "Subreddits you subscribe to on Reddit show up here, ready to add as feeds."
                )
                .pageBackground()
            } else if let summary = model.importSummary {
                EmptyStateView(
                    mark: .done,
                    title: "Subscribed",
                    message: summary,
                    actionTitle: "Done",
                    action: { dismiss() }
                )
                .pageBackground()
            } else {
                list
            }
        }
        .navigationTitle("Import subreddits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.showsSelectionControls {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.allSelected ? "Deselect all" : "Select all") {
                        model.toggleSelectAll()
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.subreddits) { sub in
                    Button {
                        model.toggle(sub.id)
                    } label: {
                        HStack {
                            Image(systemName: model.selected.contains(sub.id) ? "checkmark.circle.fill" : "circle")
                                .uiGlyph(size: Font.GlyphSize.body)
                                .foregroundStyle(model.selected.contains(sub.id) ? Accent.primary : Ink.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("r/\(sub.name)")
                                    .foregroundStyle(Ink.primary)
                                if let subs = sub.subscribers {
                                    Text("\(subs.formatted(.number.notation(.compactName))) members")
                                        .font(.caption)
                                        .foregroundStyle(Ink.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Selected subreddits are added to Feeds. Their posts appear on the next feed refresh (Reddit fetches are spaced to respect rate limits).")
            }
        }
        .pageList()
        // §8.3 — the screen's ONE prominent capsule. It was
        // `.buttonStyle(.borderedProminent)` on a `Surface.raised` plate, which
        // is a fourth button vocabulary sitting on a fifth elevation; the
        // capsule floats on the ground instead (S2 — no plate, no stroke).
        // SH3 — verb + object.
        .safeAreaInset(edge: .bottom) {
            ProminentCapsuleButton(
                title: model.selected.isEmpty
                    ? "Add feeds"
                    : "Add ^[\(model.selected.count) feed](inflect: true)",
                fillsWidth: true
            ) {
                model.subscribe(context: context)
            }
            .disabled(model.selected.isEmpty || model.isSubscribing)
            .opacity(model.selected.isEmpty || model.isSubscribing ? 0.45 : 1)
            .padding(.horizontal, Metric.screenMargin)
            .padding(.bottom, Metric.containerGap)
        }
    }
}

@MainActor
@Observable
final class RedditSubredditPickerModel {
    private(set) var subreddits: [RedditSubreddit] = []
    private(set) var isLoading = true
    private(set) var loadError: String?
    private(set) var isSubscribing = false
    /// Non-nil once a subscribe completes: a summary to show in the done state.
    private(set) var importSummary: String?
    var selected = Set<String>()

    private let reddit: RedditAuthController

    init(reddit: RedditAuthController = .shared) {
        self.reddit = reddit
    }

    var showsSelectionControls: Bool {
        !isLoading && loadError == nil && !subreddits.isEmpty && importSummary == nil
    }

    var allSelected: Bool {
        !subreddits.isEmpty && selected.count == subreddits.count
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            subreddits = try await reddit.client.subscribedSubreddits()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func toggleSelectAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = Set(subreddits.map(\.id))
        }
    }

    func subscribe(context: ModelContext) {
        guard !isSubscribing else { return }
        isSubscribing = true
        let chosen = subreddits.filter { selected.contains($0.id) }
        let created = RedditImporter.subscribe(to: chosen, context: context)
        let already = chosen.count - created
        var parts = ["Added \(created) subreddit\(created == 1 ? "" : "s") to Feeds."]
        if already > 0 { parts.append("\(already) already subscribed.") }
        importSummary = parts.joined(separator: " ")
        isSubscribing = false
    }
}
