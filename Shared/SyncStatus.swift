import Foundation

/// Observable, inspectable record of how the synced store was opened this
/// launch. `SharedModelContainer.make` sets it exactly once during scene setup;
/// Settings reads `SyncStatus.shared` to show the user whether iCloud sync is
/// active and, if not, why. There is no crash path here — every branch of
/// container creation records a state.
@Observable
final class SyncStatus {
    /// Single process-wide instance. Mutated only on the main actor during
    /// container creation (App scene setup) and read by SwiftUI on the main
    /// actor, so no cross-actor access occurs.
    static let shared = SyncStatus()

    enum State: Equatable {
        /// The synced store is mirroring to the CloudKit private database.
        case syncing
        /// The synced store is persisting locally only, for a known reason.
        case localOnly(LocalReason)
        /// No persistent store at all (unit tests / in-memory last resort).
        case unavailable
    }

    /// Why CloudKit mirroring is not active. Surfaced verbatim-ish to the user.
    enum LocalReason: Equatable {
        /// The running binary was signed without the CloudKit entitlement
        /// (every TestFlight/App Store build today, and all unsigned CI builds).
        case noEntitlement
        /// The CloudKit entitlement is present but the device has no iCloud
        /// account signed in (or iCloud is restricted/disabled).
        case noAccount
        /// CloudKit mirroring was attempted but `ModelContainer` creation threw
        /// (schema mismatch, container misprovisioned). Data still persists
        /// locally and will mirror once the problem clears on a later launch.
        case containerCreationFailed
        /// Even the plain local persistent store failed to open; the app fell
        /// back to an in-memory store for this launch.
        case persistentStoreFailed
        /// Running inside the unit-test host (hermetic in-memory store).
        case testing
    }

    private(set) var state: State = .unavailable

    // MARK: - Mirroring-event telemetry
    //
    // Populated by `SyncEventMonitor`, which listens for
    // `NSPersistentCloudKitContainer.eventChangedNotification` (SwiftData's
    // CloudKit support wraps `NSPersistentCloudKitContainer` and posts that
    // notification on the default center). These types are plain value types so
    // `SyncStatus` still compiles on every target — the CloudKit/CoreData
    // bridging lives entirely in `SyncEventMonitor`.

    /// The three phases `NSPersistentCloudKitContainer` reports. `import` is a
    /// Swift keyword, hence the `…Event` case names; `rawValue` is the wire word.
    enum SyncEventKind: String, CaseIterable, Identifiable {
        case setup
        case importEvent = "import"
        case exportEvent = "export"

        var id: String { rawValue }

        /// User-facing row label.
        var label: String {
            switch self {
            case .setup:       return "Setup"
            case .importEvent: return "Import"
            case .exportEvent: return "Export"
            }
        }
    }

    /// One mirroring event, flattened to value types. A begin-notification has a
    /// `nil` `endDate`; the matching end-notification carries `endDate`,
    /// `succeeded`, and any `error`.
    struct SyncEventRecord: Equatable {
        var kind: SyncEventKind
        var startDate: Date
        var endDate: Date?
        var succeeded: Bool
        /// Localized description of the event's error, if it failed.
        var errorDescription: String?
        /// The underlying `CKError` code (raw `Int`) when the error was one.
        var ckErrorCode: Int?

        /// True once the event has finished (import/export/setup completed).
        var isFinished: Bool { endDate != nil }

        /// A failed, finished event's human-readable error, if any.
        var failureText: String? {
            guard isFinished, !succeeded else { return nil }
            if let ckErrorCode {
                return "\(errorDescription ?? "Sync error") (CKError \(ckErrorCode))"
            }
            return errorDescription ?? "Sync error"
        }
    }

    /// Most recent event seen per kind (begin or end — whichever fired last).
    private(set) var lastEvents: [SyncEventKind: SyncEventRecord] = [:]

    /// Count of *finished* events per kind observed this launch.
    private(set) var eventCounts: [SyncEventKind: Int] = [:]

    private init() {}

    /// Records the outcome of container creation. Call once per launch.
    func update(_ newState: State) {
        state = newState
    }

    /// Records a mirroring event. Called on the main queue by
    /// `SyncEventMonitor`. Keeps the latest record per kind and tallies
    /// finished events for the session counters.
    func record(_ event: SyncEventRecord) {
        lastEvents[event.kind] = event
        if event.isFinished {
            eventCounts[event.kind, default: 0] += 1
        }
    }

    var isSyncing: Bool { state == .syncing }

    /// The last export event's failure text, if the most recent export failed.
    /// This is the signal Ellen watches: a non-nil value here means the export
    /// engine ran and errored (rendered prominently in Settings).
    var exportFailureText: String? {
        lastEvents[.exportEvent]?.failureText
    }

    /// Short, user-facing summary for the Settings screen.
    var summary: String {
        switch state {
        case .syncing:
            return "Syncing with iCloud"
        case .localOnly(let reason):
            return reason.summary
        case .unavailable:
            return "Not syncing"
        }
    }

    /// Longer explanation shown as a footnote under the summary.
    var detail: String? {
        switch state {
        case .syncing:
            return "Your library, highlights, and tags sync across your devices via your private iCloud database."
        case .localOnly(let reason):
            return reason.detail
        case .unavailable:
            return nil
        }
    }
}

extension SyncStatus.LocalReason {
    var summary: String {
        switch self {
        case .noEntitlement:      return "iCloud sync not enabled in this build"
        case .noAccount:          return "Sign in to iCloud to sync"
        case .containerCreationFailed: return "iCloud sync unavailable"
        case .persistentStoreFailed:   return "Storage unavailable"
        case .testing:            return "Testing (no sync)"
        }
    }

    var detail: String? {
        switch self {
        case .noEntitlement:
            return "This build ships without the iCloud capability. Your data is stored on this device only."
        case .noAccount:
            return "Turn on iCloud in Settings to sync your library across devices. Your data is safe on this device in the meantime."
        case .containerCreationFailed:
            return "iCloud couldn't be reached this launch. Your data is stored locally and will sync automatically once iCloud is available."
        case .persistentStoreFailed:
            return "The on-disk store couldn't be opened this launch."
        case .testing:
            return nil
        }
    }
}
