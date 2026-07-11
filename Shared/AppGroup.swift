import Foundation

enum AppGroup {
    static let identifier = "group.com.ellenbartling.readlater"
    static let iCloudContainer = "iCloud.com.ellenbartling.readlater"
    static let urlScheme = "readlater"
    static let saveDeepLinkHost = "save"
    static let openDeepLinkHost = "open"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            fatalError("App Group container missing — check entitlements for \(identifier)")
        }
        return url
    }

    static var pendingSavesURL: URL {
        let dir = containerURL.appendingPathComponent("PendingSaves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
