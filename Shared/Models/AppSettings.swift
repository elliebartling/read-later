import Foundation
import SwiftData

/// Non-synced app settings. Stored in SwiftData because it plays nicely with
/// @Query and observation. Sensitive values (OpenAI key) stay in Keychain and
/// only their reference lives here.
@Model
final class AppSettings {
    var id: UUID
    var ttsProviderRaw: String
    var ttsVoice: String
    /// Security-scoped bookmark data pointing at the user-chosen Obsidian vault folder.
    var obsidianBookmarkData: Data?
    /// Sub-folder inside the vault where markdown notes land, e.g. "Read Later".
    var obsidianSubfolder: String
    var readerThemeRaw: String
    var readerFontSize: Double
    var readerFontFamily: String

    var ttsProvider: TTSProvider {
        get { TTSProvider(rawValue: ttsProviderRaw) ?? .apple }
        set { ttsProviderRaw = newValue.rawValue }
    }

    var readerTheme: ReaderTheme {
        get { ReaderTheme(rawValue: readerThemeRaw) ?? .system }
        set { readerThemeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ttsProvider: TTSProvider = .apple,
        ttsVoice: String = "com.apple.voice.compact.en-US.Samantha",
        obsidianBookmarkData: Data? = nil,
        obsidianSubfolder: String = "Read Later",
        readerTheme: ReaderTheme = .system,
        readerFontSize: Double = 18,
        readerFontFamily: String = "New York"
    ) {
        self.id = id
        self.ttsProviderRaw = ttsProvider.rawValue
        self.ttsVoice = ttsVoice
        self.obsidianBookmarkData = obsidianBookmarkData
        self.obsidianSubfolder = obsidianSubfolder
        self.readerThemeRaw = readerTheme.rawValue
        self.readerFontSize = readerFontSize
        self.readerFontFamily = readerFontFamily
    }
}

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case apple
    case openAI

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .apple: return "Apple (offline)"
        case .openAI: return "OpenAI"
        }
    }
}

enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case light, dark, sepia, system

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}
