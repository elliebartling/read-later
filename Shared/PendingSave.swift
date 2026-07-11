import Foundation

/// A save handed off from the Share Extension to the main app. The Share
/// Extension writes one of these JSON files into the App Group container,
/// and the main app drains the queue on next foreground.
struct PendingSave: Codable, Identifiable {
    let id: UUID
    let url: URL
    let title: String?
    let capturedHTML: String?
    let source: Source
    let savedAt: Date

    enum Source: String, Codable {
        case shareExtension
        case safariWebExtension
        case urlScheme
        case manual
    }

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        capturedHTML: String? = nil,
        source: Source,
        savedAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.capturedHTML = capturedHTML
        self.source = source
        self.savedAt = savedAt
    }

    /// Writes this pending save to the shared container as `<uuid>.json`.
    /// Called from the Share Extension; drained by PendingSaveIngest.
    func write() throws {
        let data = try JSONEncoder.iso8601.encode(self)
        let dest = AppGroup.pendingSavesURL.appendingPathComponent("\(id.uuidString).json")
        try data.write(to: dest, options: .atomic)
    }

    static func loadAll() -> [PendingSave] {
        let dir = AppGroup.pendingSavesURL
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder.iso8601.decode(PendingSave.self, from: data)
            }
            .sorted { $0.savedAt < $1.savedAt }
    }

    static func remove(id: UUID) {
        let url = AppGroup.pendingSavesURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}

extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
