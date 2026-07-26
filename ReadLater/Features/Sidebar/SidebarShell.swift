import SwiftData
import SwiftUI

/// Prototype navigation shell: a Readwise-Reader-style slide-in sidebar over a
/// single content pane, instead of the TabView. Flag-gated by
/// `AppSettings.useSidebarNavigation` — when the flag is off, `RootView`
/// renders the tab bar exactly as before and none of this code runs.
///
/// Interaction model (iPhone):
/// - drag from the leading edge (or tap the floating button) to open,
/// - tap the dimmed content, drag left, or pick a row to close,
/// - each destination keeps its own `NavigationStack`, so pushes still work.
struct SidebarShell: View {
    @Environment(AppModel.self) private var appModel

    @State private var selection: SidebarDestination = .library
    @State private var isOpen = false
    @State private var dragOffset: CGFloat = 0

    /// Panel width. ~78% of a 393pt phone, matching Reader's proportion.
    private let panelWidth: CGFloat = 300
    /// Width of the invisible strip that catches the open gesture.
    private let edgeGrabWidth: CGFloat = 24

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Catches the edge swipe without stealing gestures from list rows.
            Color.clear
                .frame(width: edgeGrabWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(openDrag)
                .allowsHitTesting(!isOpen)

            Color.black
                .opacity(0.35 * progress)
                .ignoresSafeArea()
                .allowsHitTesting(progress > 0.01)
                .onTapGesture { setOpen(false) }
                .gesture(closeDrag)

            SidebarPanel(selection: $selection, onSelect: { setOpen(false) })
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .offset(x: panelX)
                .shadow(color: .black.opacity(0.25 * progress), radius: 16, x: 4)
                .gesture(closeDrag)
        }
        .overlay(alignment: .bottomLeading) {
            menuButton
                .padding(.leading, 16)
                .padding(.bottom, 20)
                .opacity(1 - progress)
                .allowsHitTesting(!isOpen)
        }
        // Deep links (readlater://open, readlater://save) still route through
        // AppModel.selectedTab, so mirror it onto the sidebar selection.
        .onChange(of: appModel.selectedTab) { _, tab in
            selection = Self.destination(for: tab)
            setOpen(false)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .library:
            LibraryView()
        case .allItems:
            SidebarFeedContainer(feed: nil)
        case .feed(let feed):
            SidebarFeedContainer(feed: feed)
                .id(feed.id)
        case .highlights:
            HighlightsView()
        case .search:
            SearchView()
        }
    }

    private var menuButton: some View {
        Button {
            setOpen(true)
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .accessibilityLabel("Show navigation")
    }

    // MARK: - Slide math

    private var panelX: CGFloat {
        let base = isOpen ? 0 : -panelWidth
        return min(0, max(-panelWidth, base + dragOffset))
    }

    /// 0 = fully closed, 1 = fully open. Drives the scrim, shadow and the
    /// floating button's fade so a partial drag looks continuous.
    private var progress: CGFloat {
        (panelX + panelWidth) / panelWidth
    }

    private var openDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isOpen else { return }
                dragOffset = max(0, value.translation.width)
            }
            .onEnded { value in
                let projected = value.translation.width + value.predictedEndTranslation.width / 4
                setOpen(projected > panelWidth / 3)
            }
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard isOpen else { return }
                dragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                let projected = value.translation.width + value.predictedEndTranslation.width / 4
                setOpen(projected > -panelWidth / 3)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.snappy(duration: 0.28)) {
            isOpen = open
            dragOffset = 0
        }
    }

    /// Maps the legacy tab identity (still set by the deep-link handler) onto a
    /// sidebar destination.
    static func destination(for tab: AppModel.Tab) -> SidebarDestination {
        switch tab {
        case .library:    return .library
        case .feeds:      return .allItems
        case .highlights: return .highlights
        case .search:     return .search
        }
    }
}

/// Hosts the existing `FeedEntriesView` (all-items river or one feed) in its
/// own NavigationStack, with the same Article → ReaderView destination the
/// Feeds tab installs. Reuse only — no fork of the entry list.
struct SidebarFeedContainer: View {
    let feed: Feed?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            FeedEntriesView(feed: feed, path: $path)
                .navigationDestination(for: Article.self) { article in
                    ReaderView(article: article)
                }
        }
    }
}
