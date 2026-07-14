import SwiftUI
import SwiftData

@main
struct ReadLaterApp: App {
    @State private var appModel = AppModel()

    /// True when this process is the host app for a unit-test run. Tests get
    /// a hermetic in-memory store — the real stores (and CloudKit) stay out
    /// of the test environment entirely.
    private static let isRunningUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
        .modelContainer(SharedModelContainer.make(inMemory: Self.isRunningUnitTests))
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
        case library, feeds, highlights, search
    }
}
