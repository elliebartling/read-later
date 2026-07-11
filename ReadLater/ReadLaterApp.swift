import SwiftUI
import SwiftData

@main
struct ReadLaterApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .onOpenURL { url in
                    appModel.handleDeepLink(url)
                }
                .task {
                    await appModel.ingestPendingSaves()
                }
        }
        .modelContainer(SharedModelContainer.make())
    }
}

@Observable
final class AppModel {
    var selectedTab: Tab = .library
    var pendingSaveError: String?

    enum Tab: Hashable {
        case library, highlights, search, settings
    }

    @MainActor
    func handleDeepLink(_ url: URL) {
        guard url.scheme == AppGroup.urlScheme else { return }
        // readlater://save?url=<encoded>
        if url.host == AppGroup.saveDeepLinkHost {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let target = components?.queryItems?.first(where: { $0.name == "url" })?.value,
               let targetURL = URL(string: target)
            {
                let pending = PendingSave(url: targetURL, source: .urlScheme)
                try? pending.write()
                Task { await ingestPendingSaves() }
            }
        }
    }

    @MainActor
    func ingestPendingSaves() async {
        await PendingSaveIngest.shared.drain()
    }
}
