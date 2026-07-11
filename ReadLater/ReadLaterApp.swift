import SwiftUI
import SwiftData

@main
struct ReadLaterApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .modelContainer(SharedModelContainer.make())
    }
}

@Observable
final class AppModel {
    var selectedTab: Tab = .library
    /// Set when a `readlater://open?id=…` deep link fires. LibraryView watches
    /// this, fetches the article, and pushes ReaderView onto its NavigationStack.
    /// Cleared once navigation lands.
    var pendingArticleToOpen: UUID?

    enum Tab: Hashable {
        case library, highlights, search, settings
    }
}
