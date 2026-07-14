import CloudKit
import CoreData
import Foundation

/// Bridges `NSPersistentCloudKitContainer`'s mirroring-event stream onto
/// `SyncStatus`. SwiftData's CloudKit support is implemented on top of
/// `NSPersistentCloudKitContainer`, and — regardless of the SwiftData wrapper —
/// the underlying container posts `NSPersistentCloudKitContainer.eventChangedNotification`
/// on `NotificationCenter.default` for every setup / import / export phase (a
/// begin notification, then a matching end notification carrying `succeeded`
/// and any `error`). That is the only public, framework-guaranteed signal into
/// SwiftData's private mirroring pipeline, so it's what we observe here.
///
/// Started only from the `.syncing` branch of `SharedModelContainer.make`, so it
/// runs only on builds that actually opened a CloudKit-mirrored store (i.e.
/// `CLOUDKIT_SYNC` device builds with an iCloud account). The `CoreData` /
/// `CloudKit` types referenced here compile on every target, so this file needs
/// no `#if` guard — activation is gated by the caller instead.
final class SyncEventMonitor {
    static let shared = SyncEventMonitor()

    private var observer: NSObjectProtocol?

    private init() {}

    /// Begins observing mirroring events. Idempotent — a second call is a no-op.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            else { return }
            SyncStatus.shared.record(Self.record(from: event))
        }
    }

    /// Translates a CloudKit mirroring event into the value-type record stored
    /// on `SyncStatus`. `static` and side-effect-free so it's unit-testable.
    static func record(from event: NSPersistentCloudKitContainer.Event) -> SyncStatus.SyncEventRecord {
        let kind: SyncStatus.SyncEventKind
        switch event.type {
        case .setup:  kind = .setup
        case .import: kind = .importEvent
        case .export: kind = .exportEvent
        @unknown default: kind = .setup
        }

        var errorDescription: String?
        var ckErrorCode: Int?
        if let error = event.error {
            errorDescription = error.localizedDescription
            if let ckError = error as? CKError {
                ckErrorCode = ckError.errorCode
            } else {
                let nsError = error as NSError
                if nsError.domain == CKErrorDomain {
                    ckErrorCode = nsError.code
                }
            }
        }

        return SyncStatus.SyncEventRecord(
            kind: kind,
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded,
            errorDescription: errorDescription,
            ckErrorCode: ckErrorCode
        )
    }
}
