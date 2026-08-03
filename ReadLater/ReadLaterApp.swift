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
                // §2.3 — the accent binding, in one place. Every system
                // control that reads the tint (toggles, sliders, tab-bar
                // selection, `Link`, prominent buttons) now resolves through
                // `Accent.primary` instead of Apple's default blue, which the
                // audit found doing accent duty by omission. v1 binds it to
                // ink; a later accent is a rebind here, not a repaint (A3).
                .tint(Accent.primary)
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
