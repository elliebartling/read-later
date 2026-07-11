import Foundation

enum AppGroup {
    static let identifier = "group.com.ellenbartling.readlater"
    static let iCloudContainer = "iCloud.com.ellenbartling.readlater"
    static let urlScheme = "readlater"
    static let saveDeepLinkHost = "save"
    static let openDeepLinkHost = "open"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // No App Group entitlement (unsigned CI/simulator builds). Degrade to
        // the app's own Application Support so in-process save flows still
        // work — extensions can't hand off in this mode, but nothing crashes.
        let fallback = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppGroupFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var pendingSavesURL: URL {
        let dir = containerURL.appendingPathComponent("PendingSaves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
