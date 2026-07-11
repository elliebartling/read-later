import Foundation
import SwiftData

enum SharedModelContainer {
    /// Container with two stores:
    /// - "synced": Article/Highlight/Tag in the CloudKit private DB
    /// - "local": AppSettings only — holds a device-specific security-scoped
    ///   bookmark that must never sync between devices
    ///
    /// Falls back gracefully when CloudKit is unavailable (no iCloud
    /// entitlement in unsigned CI builds, iCloud signed out/disabled): same
    /// store files without mirroring, and in-memory as a last resort. Never
    /// crashes at launch over sync availability.
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
            return makeInMemory(schema: fullSchema)
        }

        let syncedSchema = Schema([Article.self, Highlight.self, Tag.self])
        let localSchema = Schema([AppSettings.self])

        func localConfig() -> ModelConfiguration {
            ModelConfiguration(
                "local",
                schema: localSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }

        // Preferred: CloudKit-mirrored synced store. Only attempted when an
        // iCloud identity exists — CloudKit TRAPS (uncatchable ObjC
        // exception, not a Swift throw) when the entitlement is missing, so
        // do/catch alone cannot protect unsigned CI builds or signed-out
        // users. ubiquityIdentityToken is nil in both of those cases.
        if FileManager.default.ubiquityIdentityToken != nil {
            do {
                let synced = ModelConfiguration(
                    "synced",
                    schema: syncedSchema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .private(AppGroup.iCloudContainer)
                )
                return try ModelContainer(for: fullSchema, configurations: [synced, localConfig()])
            } catch {
                NSLog("CloudKit-backed store unavailable (%@) — falling back to local-only storage",
                      String(describing: error))
            }
        } else {
            NSLog("No iCloud identity — using local-only storage (will mirror when iCloud is available)")
        }

        // Fallback: same store files, no CloudKit mirroring. Data persists
        // and will mirror once CloudKit becomes available on a later launch.
        do {
            let synced = ModelConfiguration(
                "synced",
                schema: syncedSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: fullSchema, configurations: [synced, localConfig()])
        } catch {
            NSLog("Persistent stores unavailable (%@) — using in-memory store",
                  String(describing: error))
        }

        // Last resort: keep the app alive with an in-memory store.
        return makeInMemory(schema: fullSchema)
    }

    private static func makeInMemory(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Even the in-memory ModelContainer failed: \(error)")
        }
    }
}
