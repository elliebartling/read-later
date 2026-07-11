import Foundation
import SwiftData

/// App settings. Stored in a LOCAL-ONLY ModelConfiguration (no CloudKit) —
/// `obsidianBookmarkData` is a security-scoped bookmark, which is
/// device-specific and must never sync to another device. A single row is
/// seeded at app startup (see RootView).
///
/// Sensitive values (OpenAI key) stay in Keychain; only non-secrets live here.
@Model
final class AppSettings {
    var id: UUID = UUID()
    var ttsProviderRaw: String = TTSProvider.apple.rawValue
    /// AVSpeechSynthesisVoice identifier. Empty string = system default voice.
    var appleVoiceID: String = ""
    /// OpenAI TTS voice name (alloy, echo, fable, onyx, nova, shimmer).
    var openAIVoice: String = "alloy"
    /// Read-aloud speed multiplier (1.0 = normal). Shared by both engines.
    var ttsRate: Double = 1.0
    /// Security-scoped bookmark data pointing at the user-chosen Obsidian vault folder.
    var obsidianBookmarkData: Data?
    /// Sub-folder inside the vault where markdown notes land, e.g. "Read Later".
    var obsidianSubfolder: String = "Read Later"
    var readerThemeRaw: String = ReaderTheme.system.rawValue
    var readerFontSize: Double = 18
    /// Raw value of ReaderFont (see ReadLater/UI/ReaderFont.swift).
    var readerFontRaw: String = "Serif"

    var ttsProvider: TTSProvider {
        get { TTSProvider(rawValue: ttsProviderRaw) ?? .apple }
        set { ttsProviderRaw = newValue.rawValue }
    }

    var readerTheme: ReaderTheme {
        get { ReaderTheme(rawValue: readerThemeRaw) ?? .system }
        set { readerThemeRaw = newValue.rawValue }
    }

    init() {}
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
