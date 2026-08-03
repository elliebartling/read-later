import SwiftData
import SwiftUI

/// The slide-in navigation panel (prototype). Reader-style information
/// architecture: a couple of top-level destinations, then subscriptions grouped
/// by the kind of source they are (YouTube / Reddit / Websites), each group
/// expandable to per-feed rows with unread counts.
///
/// Everything here reads existing data — no new stored state, no new filters
/// invented for the spike.
struct SidebarPanel: View {
    @Binding var selection: SidebarDestination
    /// Called after any row tap so the shell can close itself.
    var onSelect: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(filter: #Predicate<FeedEntry> { $0.isRead == false })
    private var unreadEntries: [FeedEntry]
    @Query private var articles: [Article]

    @State private var expandedKinds: Set<FeedSourceKind> = Set(FeedSourceKind.allCases)
    @State private var showingAddFeed = false
    @State private var showingImport = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                Section {
                    row(.library, title: "Library", systemImage: "books.vertical",
                        count: articles.count)
                    row(.allItems, title: "All Items", systemImage: "tray.full",
                        count: unreadEntries.count)
                }

                if feeds.isEmpty {
                    Section("Feeds") {
                        Text("No subscriptions yet — tap + to add one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(FeedSourceKind.displayOrder) { kind in
                        let group = feeds(in: kind)
                        if !group.isEmpty {
                            Section {
                                groupDisclosure(kind: kind, feeds: group)
                            }
                        }
                    }
                }

                Section {
                    row(.highlights, title: "Highlights", systemImage: "highlighter", count: 0)
                    row(.search, title: "Search", systemImage: "magnifyingglass", count: 0)
                    Button {
                        showingSettings = true
                    } label: {
                        SidebarRowLabel(
                            title: "Settings",
                            systemImage: "gearshape",
                            count: 0,
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(.regularMaterial)
        .sheet(isPresented: $showingAddFeed) { AddFeedSheet() }
        .sheet(isPresented: $showingImport) { YouTubeImportView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Read Later")
                    .font(.title3.bold())
                Text(subscriptionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    showingAddFeed = true
                } label: {
                    Label("Add Feed…", systemImage: "link")
                }
                Button {
                    showingImport = true
                } label: {
                    Label("Import subscriptions…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(.quaternary, in: Circle())
            }
            .accessibilityLabel("Add feed")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var subscriptionSummary: String {
        let feedCount = feeds.count
        let unread = unreadEntries.count
        let feedPart = feedCount == 1 ? "1 subscription" : "\(feedCount) subscriptions"
        return unread > 0 ? "\(feedPart) · \(unread) unread" : feedPart
    }

    // MARK: - Rows

    private func row(
        _ destination: SidebarDestination,
        title: String,
        systemImage: String,
        count: Int
    ) -> some View {
        Button {
            selection = destination
            onSelect()
        } label: {
            SidebarRowLabel(
                title: title,
                systemImage: systemImage,
                count: count,
                isSelected: selection == destination
            )
        }
        .buttonStyle(.plain)
    }

    private func groupDisclosure(kind: FeedSourceKind, feeds group: [Feed]) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedKinds.contains(kind) },
                set: { expanded in
                    if expanded { expandedKinds.insert(kind) } else { expandedKinds.remove(kind) }
                }
            )
        ) {
            ForEach(group) { feed in
                Button {
                    selection = .feed(feed)
                    onSelect()
                } label: {
                    SidebarFeedRow(
                        feed: feed,
                        kind: kind,
                        unreadCount: unreadCount(for: feed),
                        isSelected: selection == .feed(feed)
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { unsubscribe(feed) } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(kind.tint)
                    .frame(width: 22)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                SidebarCountBadge(count: group.reduce(0) { $0 + unreadCount(for: $1) })
            }
        }
    }

    // MARK: - Data

    private func feeds(in kind: FeedSourceKind) -> [Feed] {
        feeds.filter { FeedSourceKind.kind(for: $0) == kind }
    }

    private func unreadCount(for feed: Feed) -> Int {
        unreadEntries.filter { $0.feed?.id == feed.id }.count
    }

    private func unsubscribe(_ feed: Feed) {
        // Never leave the shell pointing at a deleted model.
        if selection == .feed(feed) { selection = .allItems }
        context.delete(feed) // cascades to entries
        try? context.save()
    }
}

// MARK: - Row chrome

struct SidebarRowLabel: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 22)
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
            Spacer()
            SidebarCountBadge(count: count)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
    }
}

private struct SidebarFeedRow: View {
    let feed: Feed
    let kind: FeedSourceKind
    let unreadCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            SidebarAvatar(title: feed.sidebarDisplayTitle, kind: kind)
            Text(feed.sidebarDisplayTitle)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            SidebarCountBadge(count: unreadCount)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
    }
}

/// Monogram stand-in for a favicon/channel avatar. Deliberately local and
/// offline for the spike — no favicon fetching, no new network surface.
private struct SidebarAvatar: View {
    let title: String
    let kind: FeedSourceKind

    private var monogram: String {
        let stripped = title.drop(while: { !$0.isLetter && !$0.isNumber })
        guard let first = stripped.first ?? title.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        Circle()
            .fill(kind.tint.gradient)
            .frame(width: 22, height: 22)
            .overlay {
                Text(monogram)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private struct SidebarCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("\(count) unread")
        }
    }
}
