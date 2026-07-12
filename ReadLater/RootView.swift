import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: $appModel.selectedTab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppModel.Tab.library)

            HighlightsView()
                .tabItem { Label("Highlights", systemImage: "highlighter") }
                .tag(AppModel.Tab.highlights)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppModel.Tab.search)
        }
        .task {
            seedSettingsIfNeeded()
            await PendingSaveIngest.drain(context: context)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Shares saved while we were backgrounded ingest on return —
            // without this they'd sit in the App Group container until the
            // next cold start or deep link.
            if newPhase == .active {
                Task { await PendingSaveIngest.drain(context: context) }
            }
        }
        .onOpenURL { url in
            Task { await handleDeepLink(url) }
        }
    }

    /// AppSettings lives in the local-only store and is accessed via
    /// `@Query(...).first` everywhere. Seed exactly one row at startup so
    /// views never have to insert during body evaluation.
    private func seedSettingsIfNeeded() {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        if let settings = existing.first {
            // One-time split of the legacy single theme into appearance + palettes.
            if settings.readerAppearanceRaw.isEmpty {
                settings.migrateLegacyThemeIfNeeded()
                try? context.save()
            }
        } else {
            let settings = AppSettings()
            settings.migrateLegacyThemeIfNeeded()
            context.insert(settings)
            try? context.save()
        }
    }

    private func handleDeepLink(_ url: URL) async {
        guard url.scheme == AppGroup.urlScheme else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case AppGroup.saveDeepLinkHost:
            // readlater://save?url=<encoded> — used by the Safari Web Extension
            // toolbar button; write a PendingSave and drain.
            if let target = comps?.queryItems?.first(where: { $0.name == "url" })?.value,
               let targetURL = URL(string: target)
            {
                let pending = PendingSave(url: targetURL, source: .urlScheme)
                try? pending.write()
                await PendingSaveIngest.drain(context: context)
                appModel.selectedTab = .library
                appModel.pendingArticleToOpen = pending.id
            }

        case AppGroup.openDeepLinkHost:
            // readlater://open?id=<uuid> — fired by the Share Extension after
            // it writes the pending save; we drain first (which inserts the
            // stub Article using the SAME uuid) and then hand the id off to
            // LibraryView for navigation.
            guard let idStr = comps?.queryItems?.first(where: { $0.name == "id" })?.value,
                  let id = UUID(uuidString: idStr) else { return }
            appModel.selectedTab = .library
            await PendingSaveIngest.drain(context: context)
            appModel.pendingArticleToOpen = id

        default:
            break
        }
    }
}
