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
    var readerThemeRaw: String = "system"
    var readerFontSize: Double = 18
    /// Raw value of ReaderFont (see ReadLater/UI/ReaderFont.swift).
    var readerFontRaw: String = "Serif"
    /// NSParagraphStyle.lineSpacing for reader body text.
    var readerLineSpacing: Double = 6
    /// NSParagraphStyle.paragraphSpacing between reader paragraphs.
    var readerParagraphSpacing: Double = 12
    /// Raw value of ReaderWidth (column measure).
    var readerWidthRaw: String = ReaderWidth.medium.rawValue
    /// Raw value of ReaderAppearance. Empty string = not yet migrated from the
    /// legacy single readerThemeRaw (see migrateLegacyThemeIfNeeded).
    var readerAppearanceRaw: String = ""
    /// Palette used in light appearance (and system-light). Light palettes only.
    var readerLightThemeRaw: String = ReaderTheme.light.rawValue
    /// Palette used in dark appearance (and system-dark). Dark palettes only.
    var readerDarkThemeRaw: String = ReaderTheme.dark.rawValue
    /// Render block-parsed articles with the native block reader (images,
    /// captions, per-block highlighting). Off falls back to the TextKit reader.
    /// Local-only store, so no CloudKit concern.
    var useBlockReader: Bool = true
    /// Raw value of RedditDiscussionApp — where "View discussion" opens a
    /// Reddit comments permalink. Local-only store, so no CloudKit concern.
    var redditDiscussionAppRaw: String = RedditDiscussionApp.systemDefault.rawValue

    var redditDiscussionApp: RedditDiscussionApp {
        get { RedditDiscussionApp(rawValue: redditDiscussionAppRaw) ?? .systemDefault }
        set { redditDiscussionAppRaw = newValue.rawValue }
    }

    var ttsProvider: TTSProvider {
        get { TTSProvider(rawValue: ttsProviderRaw) ?? .apple }
        set { ttsProviderRaw = newValue.rawValue }
    }

    var readerWidth: ReaderWidth {
        get { ReaderWidth(rawValue: readerWidthRaw) ?? .medium }
        set { readerWidthRaw = newValue.rawValue }
    }

    var readerAppearance: ReaderAppearance {
        get { ReaderAppearance(rawValue: readerAppearanceRaw) ?? .system }
        set { readerAppearanceRaw = newValue.rawValue }
    }

    /// Falls back to .light if the stored raw is missing or a dark palette.
    var readerLightTheme: ReaderTheme {
        get {
            guard let t = ReaderTheme(rawValue: readerLightThemeRaw),
                  ReaderTheme.lightCases.contains(t) else { return .light }
            return t
        }
        set { readerLightThemeRaw = newValue.rawValue }
    }

    /// Falls back to .dark if the stored raw is missing or a light palette.
    var readerDarkTheme: ReaderTheme {
        get {
            guard let t = ReaderTheme(rawValue: readerDarkThemeRaw),
                  ReaderTheme.darkCases.contains(t) else { return .dark }
            return t
        }
        set { readerDarkThemeRaw = newValue.rawValue }
    }

    /// The concrete palette to render given the OS appearance.
    func resolvedReaderTheme(systemIsDark: Bool) -> ReaderTheme {
        switch readerAppearance {
        case .light:  return readerLightTheme
        case .dark:   return readerDarkTheme
        case .system: return systemIsDark ? readerDarkTheme : readerLightTheme
        }
    }

    /// One-time migration from the legacy single readerThemeRaw. Sentinel:
    /// an empty readerAppearanceRaw means "not migrated yet"; the method is a
    /// no-op afterwards, so user edits are never clobbered.
    func migrateLegacyThemeIfNeeded() {
        guard readerAppearanceRaw.isEmpty else { return }
        if let old = ReaderTheme(rawValue: readerThemeRaw), ReaderTheme.lightCases.contains(old) {
            readerAppearance = .light
            readerLightTheme = old
        } else if let old = ReaderTheme(rawValue: readerThemeRaw), ReaderTheme.darkCases.contains(old) {
            readerAppearance = .dark
            readerDarkTheme = old
        } else {
            // "system", unknown, or empty → system mode with default palettes.
            readerAppearance = .system
        }
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
    case light, dark, sepia
    case darkGray, mediumGray, slate, paper, forest

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .darkGray:   return "Dark Gray"
        case .mediumGray: return "Medium Gray"
        default:          return rawValue.capitalized
        }
    }

    /// Palettes offered for light appearance / system-light.
    static let lightCases: [ReaderTheme] = [.light, .sepia, .paper, .mediumGray]
    /// Palettes offered for dark appearance / system-dark.
    static let darkCases: [ReaderTheme] = [.dark, .darkGray, .slate, .forest]

    /// Fixed page darkness. Drives highlight compositing and palette grouping.
    var isDark: Bool {
        switch self {
        case .dark, .darkGray, .slate, .forest:
            return true
        case .light, .sepia, .paper, .mediumGray:
            return false
        }
    }
}

/// Where the reader's "View discussion" affordance opens a Reddit comments
/// permalink. `systemDefault` hands the reddit.com URL to the OS (official
/// Reddit app via universal links if installed, else Safari); `narwhal` uses
/// Narwhal 2's `narwhal://open-url/` scheme when it is installed; `inApp`
/// presents an in-app Safari view.
enum RedditDiscussionApp: String, Codable, CaseIterable, Identifiable {
    case systemDefault
    case narwhal
    case inApp

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .systemDefault: return "System Default"
        case .narwhal: return "Narwhal"
        case .inApp: return "In-App Browser"
        }
    }
}

enum ReaderAppearance: String, Codable, CaseIterable, Identifiable {
    case light, dark, system

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
