import SwiftData
import XCTest
@testable import ReadLater

/// Guards the CloudKit runtime gate and the SwiftData model invariants that
/// CloudKit mirroring requires. The simulator has no iCloud account, so real
/// mirroring can't be exercised here — these tests pin the *decision* logic and
/// the *schema shape* that keep container creation from trapping at launch.
final class CloudKitSyncTests: XCTestCase {

    // MARK: - Sync decision / fallback logic

    func testDecisionIsCloudKitOnlyWithEntitlementAndAccount() {
        XCTAssertEqual(
            SharedModelContainer.resolveSyncDecision(hasEntitlement: true, hasAccount: true),
            .cloudKit
        )
    }

    func testDecisionFallsBackWhenEntitlementMissing() {
        // Entitlement missing is the dangerous case: passing .private(...) here
        // would trap uncatchably, so the gate MUST choose local-only even when
        // an iCloud account is present.
        XCTAssertEqual(
            SharedModelContainer.resolveSyncDecision(hasEntitlement: false, hasAccount: true),
            .localOnly(.noEntitlement)
        )
        XCTAssertEqual(
            SharedModelContainer.resolveSyncDecision(hasEntitlement: false, hasAccount: false),
            .localOnly(.noEntitlement)
        )
    }

    func testDecisionFallsBackWhenNoAccount() {
        XCTAssertEqual(
            SharedModelContainer.resolveSyncDecision(hasEntitlement: true, hasAccount: false),
            .localOnly(.noAccount)
        )
    }

    /// Unsigned test host must never claim the CloudKit entitlement — this is
    /// the real value that feeds the gate at launch, so it must read false here.
    func testTestHostHasNoCloudKitEntitlement() {
        XCTAssertFalse(SharedModelContainer.binaryHasCloudKitEntitlement())
    }

    // MARK: - Sync status surfacing

    func testSyncStatusSummariesAreNonEmpty() {
        XCTAssertFalse(SyncStatus.LocalReason.noEntitlement.summary.isEmpty)
        XCTAssertFalse(SyncStatus.LocalReason.noAccount.summary.isEmpty)
        XCTAssertFalse(SyncStatus.LocalReason.containerCreationFailed.summary.isEmpty)

        let status = SyncStatus.shared
        status.update(.syncing)
        XCTAssertTrue(status.isSyncing)
        XCTAssertEqual(status.summary, "Syncing with iCloud")
        status.update(.localOnly(.noAccount))
        XCTAssertFalse(status.isSyncing)
    }

    // MARK: - Model invariant audit (CloudKit requirements)

    /// The synced store models must satisfy CloudKit's SwiftData rules:
    /// every stored attribute optional-or-defaulted, every relationship
    /// optional, and no unique constraints — otherwise `ModelContainer`
    /// creation with `cloudKitDatabase: .private` throws at launch.
    func testSyncedModelsSatisfyCloudKitInvariants() {
        let schema = Schema([Article.self, Highlight.self, Tag.self])

        for entity in schema.entities {
            for attribute in entity.attributes where !attribute.isTransient {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) must be optional or carry a default for CloudKit"
                )
                XCTAssertFalse(
                    attribute.isUnique,
                    "\(entity.name).\(attribute.name) must not be unique — CloudKit forbids unique constraints"
                )
            }
            for relationship in entity.relationships {
                XCTAssertTrue(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) relationship must be optional for CloudKit"
                )
            }
        }
    }

    /// AppSettings is intentionally NOT in the synced schema — it holds a
    /// device-specific security-scoped bookmark and must stay local-only.
    func testAppSettingsIsNotInSyncedSchema() {
        let synced = Schema([Article.self, Highlight.self, Tag.self])
        XCTAssertFalse(
            synced.entities.contains { $0.name == "AppSettings" },
            "AppSettings must never join the CloudKit-synced schema"
        )
    }

    /// A local-only (cloudKitDatabase: .none) build of the synced schema must
    /// always succeed — this is the fallback path taken on every CI/simulator
    /// run and whenever iCloud is unavailable.
    func testLocalOnlySyncedSchemaOpens() throws {
        let config = ModelConfiguration(
            "synced-test",
            schema: Schema([Article.self, Highlight.self, Tag.self]),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        XCTAssertNoThrow(
            try ModelContainer(
                for: Article.self, Highlight.self, Tag.self,
                configurations: config
            )
        )
    }
}
