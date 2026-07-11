import Foundation
import SwiftData

enum SharedModelContainer {
    /// Container with two stores:
    /// - "synced": Article/Highlight/Tag in the CloudKit private DB
    /// - "local": AppSettings only — holds a device-specific security-scoped
    ///   bookmark that must never sync between devices
    ///
    /// The Share Extension does NOT open this; it writes a PendingSave JSON
    /// instead, so it stays fast and avoids fighting with the app for the
    /// CloudKit sync channel.
    static func make(inMemory: Bool = false) -> ModelContainer {
        let fullSchema = Schema([
            Article.self,
            Highlight.self,
            Tag.self,
            AppSettings.self,
        ])

        if inMemory {
            let config = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: fullSchema, configurations: [config])
            } catch {
                fatalError("Failed to create in-memory ModelContainer: \(error)")
            }
        }

        let syncedSchema = Schema([Article.self, Highlight.self, Tag.self])
        let localSchema = Schema([AppSettings.self])

        let synced = ModelConfiguration(
            "synced",
            schema: syncedSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(AppGroup.iCloudContainer)
        )
        let local = ModelConfiguration(
            "local",
            schema: localSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: fullSchema, configurations: [synced, local])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
