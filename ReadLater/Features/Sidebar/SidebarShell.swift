import SwiftData
import SwiftUI

/// The app's navigation. Layered, not a drawer (Ellen, issue #57).
///
/// ```
/// layer 2   reader          ── a normal NavigationStack push
/// layer 1   group / list    ── a full-height card floating over the sidebar
/// layer 0   sidebar         ── the root; sources, views, Settings
/// ```
///
/// **One gesture peels one layer.** Inside the card the system's interactive
/// pop takes reader → list, untouched. At the card's root our screen-edge pan
/// takes list → sidebar: the card tracks the finger, the sidebar parallaxes up
/// from behind and un-dims, and the throw decides whether it commits or snaps
/// back (`PeelGeometry`). A trailing-edge pan brings the card back, so a peel
/// is never a one-way door.
///
/// What this replaced: the tab bar, the `useSidebarNavigation` experiment flag,
/// the floating sidebar button, and the old global edge-drag-from-anywhere
/// drawer — that last one conflicted with the reader's back-swipe, which is
/// what made the prototype fail its trial.
struct SidebarShell: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which group the card is showing.
    @State private var selection: SidebarDestination = .library
    /// Layer 2. One stack per card; picking a new source starts a fresh one.
    @State private var path = NavigationPath()
    /// Whether the card covers the sidebar.
    @State private var isCardPresented = true
    /// Live peel translation while a finger is down; `nil` at rest.
    @State private var dragTranslation: CGFloat?
    /// Shell width, measured rather than read from a `GeometryReader` wrapper
    /// so the layers keep their natural safe areas.
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            sidebarLayer
            cardLayer
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: ShellWidthKey.self, value: geometry.size.width)
            }
        }
        .onPreferenceChange(ShellWidthKey.self) { width = $0 }
        .background {
            // Leading edge: peel the card off the sidebar. Only at the card's
            // root — one layer deeper this gesture is the reader's own pop.
            EdgePanCatcher(
                edge: .leading,
                isEnabled: isCardPresented && path.isEmpty,
                onChanged: { dragTranslation = $0 },
                onEnded: { endPeel(translation: $0, velocity: $1) }
            )
            // Trailing edge: put the card back without going via a row tap.
            EdgePanCatcher(
                edge: .trailing,
                isEnabled: !isCardPresented,
                onChanged: { dragTranslation = $0 },
                onEnded: { endPeel(translation: $0, velocity: $1) }
            )
        }
        .task(id: appModel.pendingArticleToOpen) {
            await handlePendingOpen()
        }
    }

    // MARK: - Layer 0 — the sidebar

    private var sidebarLayer: some View {
        SidebarPanel(
            selection: selection,
            onSelect: { show($0) },
            // A source that goes away (unsubscribe) must not leave the card
            // pointing at a deleted model — but it is not a navigation either,
            // so it never brings the card forward.
            onInvalidate: { replacement in
                selection = replacement
                path = NavigationPath()
            }
        )
        .offset(x: PeelGeometry.sidebarParallax(progress: progress, width: width))
        .overlay {
            Color.black
                .opacity(PeelGeometry.dim(progress: progress))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        // While the card covers it the sidebar is decoration, not content.
        .accessibilityHidden(progress < 0.5)
    }

    // MARK: - Layer 1 — the group/list card

    private var cardLayer: some View {
        NavigationStack(path: $path) {
            destinationRoot
                .navigationDestination(for: Article.self) { article in
                    ReaderView(article: article)
                }
        }
        // The card carries the page ground itself, so its corners never show
        // the sidebar through as they round off.
        .background(Surface.ground)
        .clipShape(
            .rect(cornerRadius: PeelGeometry.cornerRadius(progress: progress), style: .continuous)
        )
        .shadow(
            color: .black.opacity(
                (colorScheme == .dark ? 0.18 : 0.10) * PeelGeometry.shadowScale(progress: progress)
            ),
            radius: 16 / 2, // SwiftUI radius is ~half a CSS blur
            x: -4
        )
        .offset(x: cardOffset)
        .ignoresSafeArea()
        // A card that has been peeled away is off-screen scenery: it must not
        // keep hit-testing, or every tap on the sidebar beneath it is
        // swallowed by an invisible list. (`.offset` alone does not move the
        // interactive region out of the way once the layer ignores the safe
        // area.)
        .allowsHitTesting(isCardPresented)
        // The affordance exists only where peeling is what "back" means.
        .environment(\.peelToSidebar, path.isEmpty ? { peel() } : nil)
        .accessibilityHidden(progress > 0.5)
    }

    @ViewBuilder
    private var destinationRoot: some View {
        switch selection {
        case .library:
            LibraryView()
        case .allItems:
            FeedEntriesView(feed: nil, path: $path)
        case .feed(let feed):
            FeedEntriesView(feed: feed, path: $path)
                .id(feed.id)
        case .highlights:
            HighlightsView()
        case .search:
            SearchView()
        }
    }

    // MARK: - Peel mechanics

    /// Where the card would sit with no finger down.
    private var restingOffset: CGFloat { isCardPresented ? 0 : width }

    private var cardOffset: CGFloat {
        guard width > 0 else { return 0 }
        return PeelGeometry.offset(
            base: restingOffset,
            translation: dragTranslation ?? 0,
            width: width
        )
    }

    private var progress: CGFloat {
        PeelGeometry.progress(offset: cardOffset, width: width)
    }

    private var peelAnimation: Animation {
        Motion.resolve(Motion.standard, reduceMotion: reduceMotion)
    }

    private func endPeel(translation: CGFloat, velocity: CGFloat) {
        let landed = PeelGeometry.offset(
            base: restingOffset, translation: translation, width: width
        )
        let peels = PeelGeometry.shouldPeel(offset: landed, velocity: velocity, width: width)
        withAnimation(peelAnimation) {
            dragTranslation = nil
            isCardPresented = !peels
        }
    }

    /// Peel to the sidebar (the toolbar chevron, and VoiceOver's route).
    private func peel() {
        withAnimation(peelAnimation) {
            dragTranslation = nil
            isCardPresented = false
        }
    }

    /// Show a group: the card slides back over the sidebar with that group at
    /// the root of a fresh stack.
    private func show(_ destination: SidebarDestination) {
        if destination != selection {
            path = NavigationPath()
            selection = destination
        }
        withAnimation(peelAnimation) {
            dragTranslation = nil
            isCardPresented = true
        }
    }

    // MARK: - Deep links

    /// `readlater://open?id=…` and `readlater://save?url=…` both end here.
    /// The article is layer 2, so the layers beneath it have to be right
    /// before it lands: Library at layer 1, card presented over the sidebar,
    /// and a stack with exactly the article on it — so the reader's back-swipe
    /// returns to Library and a second peel reaches the sidebar.
    private func handlePendingOpen() async {
        guard let id = appModel.pendingArticleToOpen else { return }
        selection = .library
        show(.library)

        // Poll briefly: the deep-link handler drains PendingSaves before
        // setting this ID, but SwiftData's fetch may take a beat to surface
        // the freshly-inserted row.
        for _ in 0..<40 {
            if let target = fetchArticle(id: id) {
                path = NavigationPath()
                path.append(target)
                appModel.pendingArticleToOpen = nil
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        appModel.pendingArticleToOpen = nil
    }

    private func fetchArticle(id: UUID) -> Article? {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct ShellWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
