import Foundation
import SwiftData

enum SharedModelContainer {
    /// The synced store mirrors to the CloudKit private database **only when
    /// the running binary was actually signed with the CloudKit entitlement**
    /// (see `binaryHasCloudKitEntitlement`) *and* an iCloud identity exists.
    ///
    /// Why gate on the entitlement instead of a compile-time flag:
    ///
    /// - CloudKit mirroring TRAPS uncatchably (an ObjC exception on
    ///   `com.apple.coredata.cloudkit.queue`, not a Swift `throw`) when the
    ///   entitlement is missing, so a `do/catch` alone cannot protect a build
    ///   that lacks it. The only safe move is to never pass `.private(...)`
    ///   unless the entitlement is present in the signed binary.
    /// - Release/TestFlight builds are signed with app-group-only entitlements
    ///   (`ReadLater.release.entitlements`), so this check returns `false`
    ///   there and the app stays local-only automatically — the same source
    ///   ships to every configuration and behaves correctly without a flag.
    /// - Debug/dev builds signed with `ReadLater.entitlements` carry the
    ///   CloudKit entitlement and use the **Development** CloudKit environment,
    ///   where SwiftData auto-initializes the schema (no manual deploy needed),
    ///   so the Production-schema trap described below cannot fire.
    ///
    /// Production-schema caveat (relevant only once Release ships CloudKit):
    /// TestFlight/App Store use the **Production** CloudKit environment. Before
    /// flipping `ReadLater.release.entitlements` to include CloudKit, the schema
    /// MUST be deployed to Production (CloudKit Console → Deploy Schema to
    /// Production); otherwise mirroring aborts uncatchably at launch. See
    /// docs/cloudkit-rollout.md for the ordered rollout steps.

    /// The set of models that live in the CloudKit-mirrored "synced" store.
    /// `AppSettings` is deliberately excluded — it lives in a local-only store.
    private static var syncedModels: [any PersistentModel.Type] {
        [Article.self, Highlight.self, Tag.self]
    }

    /// Container with two stores:
    /// - "synced": Article/Highlight/Tag, optionally in the CloudKit private DB
    /// - "local": AppSettings only — holds a device-specific security-scoped
    ///   bookmark that must never sync between devices
    ///
    /// Never throws to the caller: every failure path degrades (CloudKit →
    /// local files → in-memory) and records the outcome on `SyncStatus.shared`
    /// so Settings can show what happened.
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
            SyncStatus.shared.update(.localOnly(.testing))
            return makeInMemory(schema: fullSchema)
        }

        let decision = resolveSyncDecision(
            hasEntitlement: binaryHasCloudKitEntitlement(),
            hasAccount: FileManager.default.ubiquityIdentityToken != nil
        )

        switch decision {
        case .cloudKit:
            // Preferred: CloudKit-mirrored synced store. Reached only when the
            // entitlement is present in the signed binary, so passing
            // `.private(...)` cannot hit the missing-entitlement trap.
            do {
                let synced = ModelConfiguration(
                    "synced",
                    schema: Schema(syncedModels),
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .private(AppGroup.iCloudContainer)
                )
                let container = try ModelContainer(
                    for: fullSchema,
                    configurations: [synced, localConfig()]
                )
                SyncStatus.shared.update(.syncing)
                return container
            } catch {
                NSLog("CloudKit-backed store unavailable (%@) — falling back to local-only storage",
                      String(describing: error))
                return makeLocalOnly(fullSchema: fullSchema, reason: .containerCreationFailed)
            }

        case .localOnly(let reason):
            NSLog("CloudKit sync disabled (%@) — using local-only storage", String(describing: reason))
            return makeLocalOnly(fullSchema: fullSchema, reason: reason)
        }
    }

    /// Pure decision function so the gate/fallback logic is unit-testable
    /// without a real entitlement or iCloud account. In-memory/test handling
    /// happens before this is called.
    static func resolveSyncDecision(hasEntitlement: Bool, hasAccount: Bool) -> SyncDecision {
        guard hasEntitlement else { return .localOnly(.noEntitlement) }
        guard hasAccount else { return .localOnly(.noAccount) }
        return .cloudKit
    }

    enum SyncDecision: Equatable {
        case cloudKit
        case localOnly(SyncStatus.LocalReason)
    }

    // MARK: - Store builders

    private static func localConfig() -> ModelConfiguration {
        ModelConfiguration(
            "local",
            schema: Schema([AppSettings.self]),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }

    /// Same store files as the CloudKit path, but without mirroring. Data
    /// persists and will mirror once CloudKit becomes available on a later
    /// launch. Falls back to in-memory only if the persistent store itself
    /// fails to open.
    private static func makeLocalOnly(fullSchema: Schema, reason: SyncStatus.LocalReason) -> ModelContainer {
        do {
            let synced = ModelConfiguration(
                "synced",
                schema: Schema(syncedModels),
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: fullSchema,
                configurations: [synced, localConfig()]
            )
            SyncStatus.shared.update(.localOnly(reason))
            return container
        } catch {
            NSLog("Persistent stores unavailable (%@) — using in-memory store",
                  String(describing: error))
            SyncStatus.shared.update(.localOnly(.persistentStoreFailed))
            return makeInMemory(schema: fullSchema)
        }
    }

    private static func makeInMemory(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Even the in-memory ModelContainer failed: \(error)")
        }
    }

    // MARK: - Entitlement detection

    /// True only when this build can safely open a CloudKit-mirrored store.
    /// Deliberately AND-gates two independent signals, because iOS exposes no
    /// public API to read a running process's own signed entitlements
    /// (`SecTask`/`SecCode` entitlement reads are macOS-only):
    ///
    /// 1. **Compile condition `CLOUDKIT_SYNC`** — defined (via project.yml)
    ///    only for the build config whose `CODE_SIGN_ENTITLEMENTS` file carries
    ///    CloudKit (Debug → `ReadLater.entitlements`). Release/TestFlight is
    ///    signed with the app-group-only entitlements and does NOT define it,
    ///    so this returns `false` there regardless of anything else — that is
    ///    what keeps the TestFlight binary from ever attempting `.private(...)`.
    ///
    /// 2. **Provisioning-profile check** — the app's App ID/profile must
    ///    actually grant the iCloud capability. During the current rollout the
    ///    dev profile does NOT yet include iCloud, so even a Debug build on a
    ///    real device must stay local-only or CloudKit mirroring traps
    ///    uncatchably at launch. On the simulator and in unsigned CI there is
    ///    no embedded profile, so this is `false` (correct: no account there
    ///    either).
    ///
    /// Both true ⇒ the signed binary carries the CloudKit entitlement AND the
    /// profile grants it ⇒ mirroring is safe to attempt.
    static func binaryHasCloudKitEntitlement() -> Bool {
        #if CLOUDKIT_SYNC
        return provisioningProfileGrantsCloudKit()
        #else
        return false
        #endif
    }

    /// Parses the app's embedded `embedded.mobileprovision` and reports whether
    /// its entitlements grant the iCloud/CloudKit capability. Returns `false`
    /// when no profile is embedded (simulator, unsigned CI) or when the profile
    /// predates the iCloud capability being added to the App ID.
    static func provisioningProfileGrantsCloudKit() -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              // The profile is a CMS/PKCS#7 blob; the entitlements are an ASCII
              // XML plist embedded inside it. Latin-1 maps every byte losslessly
              // so the <plist>…</plist> slice survives extraction.
              let text = String(data: raw, encoding: .isoLatin1),
              let start = text.range(of: "<plist"),
              let end = text.range(of: "</plist>")
        else { return false }

        let plistSlice = String(text[start.lowerBound ..< end.upperBound])
        guard let plistData = plistSlice.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = plist as? [String: Any],
              let entitlements = dict["Entitlements"] as? [String: Any]
        else { return false }

        if let services = entitlements["com.apple.developer.icloud-services"] as? [String] {
            return services.contains("CloudKit")
        }
        // Development profiles often carry the wildcard form.
        if let services = entitlements["com.apple.developer.icloud-services"] as? String {
            return services == "CloudKit" || services == "*"
        }
        // Fallback: an iCloud container list present at all means the App ID
        // has the capability.
        if let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] {
            return !containers.isEmpty
        }
        return false
    }
}
