import Foundation
import SwiftData

enum SharedModelContainer {
    /// Full container with CloudKit sync — used by the main app.
    /// The Share Extension does NOT open this; it writes a PendingSave JSON
    /// instead, so it stays fast and avoids fighting with the app for the
    /// CloudKit sync channel.
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Article.self,
            Highlight.self,
            Tag.self,
            AppSettings.self,
        ])

        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(AppGroup.iCloudContainer)
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
