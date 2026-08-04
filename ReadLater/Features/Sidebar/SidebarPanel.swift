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
/// Constitution notes:
/// - separators are off (S2/N2), and so — since Ellen's build-43 review — are
///   the section CARDS. The sidebar is the app's ground floor and reads as one
///   continuous surface: headers and rows sit directly on `Surface.ground` and
///   whitespace does the separating. See `sidebarList()` for the reasoning and
///   for why this is the one list in the app that is not `pageList()`.
/// - one row grammar: a rounded-square identity tile at the small tier, a
///   `.body` label, a trailing count; selection is a single `Accent.muted`
///   wash pill on the ground (A1), never a tint on the text and never a pill
///   nested inside a card.
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
                row(.library, title: "Library", systemImage: "books.vertical",
                    count: articles.count)
                row(.allItems, title: "All items", systemImage: "tray.full",
                    count: unreadEntries.count)

                if feeds.isEmpty {
                    Text("No subscriptions yet — tap + to add one.")
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                        .padding(.vertical, Metric.rowVerticalPadding)
                        .sidebarRow(topGap: Metric.containerGap)
                } else {
                    ForEach(Array(FeedSourceKind.displayOrder.enumerated()), id: \.element) { pair in
                        let group = feeds(in: pair.element)
                        if !group.isEmpty {
                            groupDisclosure(kind: pair.element, feeds: group)
                                // Whitespace, not a surface, separates groups.
                                .sidebarRow(topGap: Metric.containerGap)
                        }
                    }
                }

                row(.highlights, title: "Highlights", systemImage: "highlighter",
                    count: highlights.count, topGap: Metric.containerGap)
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
                .sidebarRow()
            }
            .sidebarList()
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
                // I5 — glyphs are banned from menu items: the label already
                // carries the meaning, so the icon is decoration (N3). T7 —
                // sentence case, which this menu previously mixed with title
                // case one item apart.
                Button("Add feed…") { showingAddFeed = true }
                Button("Import subscriptions…") { showingImport = true }
            } label: {
                Image(systemName: "plus")
                    .uiGlyph()
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

    private func row(
        _ destination: SidebarDestination,
        title: String,
        systemImage: String,
        count: Int,
        topGap: CGFloat = 0
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
        .sidebarRow(topGap: topGap)
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
                .sidebarRow()
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { unsubscribe(feed) } label: {
                        Label("Unsubscribe", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                SourceKindChip(kind: kind)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 8)
                SidebarCountBadge(count: group.reduce(0) { $0 + unreadCount(for: $1) })
            }
            .frame(minHeight: ControlTier.hitTarget)
            // ONE left inset for every row in this list (S3). The row labels
            // carry the same 8pt, so a group header's mark and a destination
            // row's glyph start at the same x.
            .padding(.horizontal, 8)
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
        // Never leave the card pointing at a deleted model.
        if selection == .feed(feed) { onInvalidate(.allItems) }
        context.delete(feed) // cascades to entries
        try? context.save()
    }
}

// MARK: - Row chrome

struct SidebarRowLabel: View {
    /// The selection pill's corner. One value, shared with the feed rows so a
    /// selected feed and a selected destination are the same shape.
    static let selectionRadius: CGFloat = 12

    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // I2 — one weight, one scale, sized to the label beside it.
            Image(systemName: systemImage)
                .uiGlyph()
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
    /// One soft wash pill, directly on the ground: there is no card under it to
    /// nest inside any more, so it carries the container radius itself rather
    /// than a radius derived from a parent that no longer exists (Z3).
    @ViewBuilder
    private var selectionWash: some View {
        RoundedRectangle(cornerRadius: SidebarRowLabel.selectionRadius, style: .continuous)
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
            SidebarAvatar(feed: feed, kind: kind)
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
            RoundedRectangle(cornerRadius: SidebarRowLabel.selectionRadius, style: .continuous)
                .fill(isSelected ? Accent.muted : .clear)
        )
    }
}

/// **BR1 / BR2.** A subscription's identity mark: the site's own favicon on a
/// `Surface.control` tile, with the monogram on the source hue standing in
/// until (or instead of) one. Wave 3 built `FaviconTile` to drop in here
/// unchanged — the sidebar's hand-rolled monogram circle was the prototype the
/// component was modelled on, so adopting it deletes the duplicate rather than
/// changing the design.
private struct SidebarAvatar: View {
    let feed: Feed
    let kind: FeedSourceKind

    var body: some View {
        FaviconTile(
            host: feed.siteURL?.host ?? feed.feedURL?.host,
            title: feed.sidebarDisplayTitle,
            tint: kind.tint
        )
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
