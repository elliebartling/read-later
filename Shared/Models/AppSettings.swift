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
    /// NSParagraphStyle.lineSpacing for reader body text.
    var readerLineSpacing: Double = 6
    /// NSParagraphStyle.paragraphSpacing between reader paragraphs.
    var readerParagraphSpacing: Double = 12
    /// Raw value of ReaderWidth (column measure).
    var readerWidthRaw: String = ReaderWidth.medium.rawValue

    var ttsProvider: TTSProvider {
        get { TTSProvider(rawValue: ttsProviderRaw) ?? .apple }
        set { ttsProviderRaw = newValue.rawValue }
    }

    var readerTheme: ReaderTheme {
        get { ReaderTheme(rawValue: readerThemeRaw) ?? .system }
        set { readerThemeRaw = newValue.rawValue }
    }

    var readerWidth: ReaderWidth {
        get { ReaderWidth(rawValue: readerWidthRaw) ?? .medium }
        set { readerWidthRaw = newValue.rawValue }
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

enum ReaderWidth: String, Codable, CaseIterable, Identifiable {
    case narrow, medium, wide, full

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Left/right `textContainerInset` in points. Narrower column = larger inset.
    var horizontalInset: CGFloat {
        switch self {
        case .narrow: return 48
        case .medium: return 32
        case .wide:   return 20
        case .full:   return 12
        }
    }
}
