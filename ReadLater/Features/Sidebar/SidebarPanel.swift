import SwiftData
import SwiftUI

/// Layer 0 — the app's root. A couple of top-level destinations, then
/// subscriptions grouped by the kind of source they are (YouTube / Reddit /
/// Websites), each group expandable to per-feed rows with unread counts, then
/// the views that aren't sources: Highlights, Search, Settings.
///
/// Settings lives here because the list views' leading toolbar slot is the
/// back-to-sidebar affordance now (issue #57) — nothing in the app is
/// unreachable without it.
///
/// Constitution notes for the wave-4 cleanup:
/// - separators are off (S2/N2): rows are separated by the E0→E1 value step
///   and the gap between containers, which is also what fixes the audit's
///   "four different left insets in one list".
/// - one row grammar: a `Surface.control` tile or monogram at the small tier,
///   a `.body` label, a trailing count; selection is an `Accent.muted` wash at
///   every level (A1), never a tint on the text.
/// - one glyph weight and scale (I2); the header is display tier (T4).
struct SidebarPanel: View {
    /// What the card is showing, so the matching row reads as selected.
    let selection: SidebarDestination
    /// A row tap: change the group and bring the card forward.
    var onSelect: (SidebarDestination) -> Void
    /// The selection stopped being valid (its feed was deleted). Replace it,
    /// but don't navigate.
    var onInvalidate: (SidebarDestination) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(filter: #Predicate<FeedEntry> { $0.isRead == false })
    private var unreadEntries: [FeedEntry]
    @Query private var articles: [Article]
    @Query private var highlights: [Highlight]

    @State private var expandedKinds: Set<FeedSourceKind> = Set(FeedSourceKind.allCases)
    @State private var showingAddFeed = false
    @State private var showingImport = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            // No rule under the header (S2). The header's own padding and the
            // list's ground are the separation.
            List {
                Section {
                    row(.library, title: "Library", systemImage: "books.vertical",
                        count: articles.count)
                    row(.allItems, title: "All items", systemImage: "tray.full",
                        count: unreadEntries.count)
                }

                if feeds.isEmpty {
                    Section("Subscriptions") {
                        Text("No subscriptions yet — tap + to add one.")
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                            .listRowInsets(Self.rowInsets)
                            .padding(.vertical, Metric.rowVerticalPadding)
                            .listRowSeparator(.hidden)
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
                    row(.highlights, title: "Highlights", systemImage: "highlighter",
                        count: highlights.count)
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
                    .listRowInsets(Self.rowInsets)
                    .listRowSeparator(.hidden)
                }
            }
            .pageList()
        }
        .background(Surface.ground)
        .sheet(isPresented: $showingAddFeed) { AddFeedSheet() }
        .sheet(isPresented: $showingImport) { YouTubeImportView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    /// The one display-tier string in the shell (§4.3 — "screen titles,
    /// sidebar header").
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Read Later")
                    .displayType(DisplayType.displaySmall)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subscriptionSummary)
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Metric.containerPadding)
            Menu {
                Button {
                    showingAddFeed = true
                } label: {
                    Label("Add feed…", systemImage: "link")
                }
                Button {
                    showingImport = true
                } label: {
                    Label("Import subscriptions…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: ControlTier.standard.glyph, weight: .medium))
                    .foregroundStyle(Accent.primary)
                    // Standard tier — there is no 32pt tier (Z2).
                    .frame(width: ControlTier.standard.height,
                           height: ControlTier.standard.height)
                    .background(Surface.control, in: Circle())
            }
            .accessibilityLabel("Add feed")
        }
        .padding(.horizontal, Metric.screenMargin)
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

    /// One inset for every row in the list (S3's complaint was four).
    static let rowInsets = EdgeInsets(
        top: 0, leading: Metric.containerPadding,
        bottom: 0, trailing: Metric.containerPadding
    )

    private func row(
        _ destination: SidebarDestination,
        title: String,
        systemImage: String,
        count: Int
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            SidebarRowLabel(
                title: title,
                systemImage: systemImage,
                count: count,
                isSelected: selection == destination
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(Self.rowInsets)
        .listRowSeparator(.hidden)
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
                    onSelect(.feed(feed))
                } label: {
                    SidebarFeedRow(
                        feed: feed,
                        kind: kind,
                        unreadCount: unreadCount(for: feed),
                        isSelected: selection == .feed(feed)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(Self.rowInsets)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { unsubscribe(feed) } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                SidebarKindChip(kind: kind)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 8)
                SidebarCountBadge(count: group.reduce(0) { $0 + unreadCount(for: $1) })
            }
            .frame(minHeight: ControlTier.hitTarget)
        }
        .listRowInsets(Self.rowInsets)
        .listRowSeparator(.hidden)
    }

    // MARK: - Data

    private func feeds(in kind: FeedSourceKind) -> [Feed] {
        feeds.filter { FeedSourceKind.kind(for: $0) == kind }
    }

    private func unreadCount(for feed: Feed) -> Int {
        unreadEntries.filter { $0.feed?.id == feed.id }.count
    }

    private func unsubscribe(_ feed: Feed) {
        // Never leave the card pointing at a deleted model.
        if selection == .feed(feed) { onInvalidate(.allItems) }
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
            // I2 — one weight, one scale, sized to the label beside it.
            Image(systemName: systemImage)
                .font(.system(size: ControlTier.standard.glyph, weight: .medium))
                .foregroundStyle(isSelected ? Accent.primary : Ink.secondary)
                .frame(width: 24)
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            SidebarCountBadge(count: count)
        }
        // Standard tier: a list row is a 44pt control (§7.1).
        .frame(minHeight: ControlTier.hitTarget)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(selectionWash)
    }

    /// A1 — selection is `Accent.muted`, never an `Ink`/`Surface` shortcut.
    @ViewBuilder
    private var selectionWash: some View {
        RoundedRectangle(cornerRadius: Radius.nested(in: Radius.container, padding: 8),
                         style: .continuous)
            .fill(isSelected ? Accent.muted : .clear)
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
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            SidebarCountBadge(count: unreadCount)
        }
        .frame(minHeight: ControlTier.hitTarget)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Radius.nested(in: Radius.container, padding: 8),
                             style: .continuous)
                .fill(isSelected ? Accent.muted : .clear)
        )
    }
}

/// The kind marker for a group header. I7 — a glyph is chipped when it
/// *identifies a thing*, and a source kind is a thing. Small tier (§7.1).
private struct SidebarKindChip: View {
    let kind: FeedSourceKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: ControlTier.small.glyph, weight: .medium))
            .foregroundStyle(Accent.onFill)
            .frame(width: ControlTier.small.height, height: ControlTier.small.height)
            .background(kind.tint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Monogram stand-in for a favicon/channel avatar (BR2). Local and offline —
/// favicon fetching is wave 3's, not this wave's.
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
            // Flat fill: a gradient inside a source mark is decoration that
            // answers nothing (N3), and BR3 wants one fidelity per column.
            .fill(kind.tint)
            .frame(width: ControlTier.small.height, height: ControlTier.small.height)
            .overlay {
                Text(monogram)
                    .font(.caption.weight(.semibold))
                    // A2 — never hardcoded white.
                    .foregroundStyle(Accent.onFill)
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
                .foregroundStyle(Ink.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                // T8 — a count is arbitrary content; it never wraps.
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
