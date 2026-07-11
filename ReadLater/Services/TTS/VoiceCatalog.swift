import Foundation
import AVFoundation

/// Voice lists + display names shared by Settings and the reader's player bar.
enum VoiceCatalog {
    /// Voices documented for OpenAI's speech API (gpt-4o-mini-tts).
    static let openAIVoices = [
        "alloy", "ash", "ballad", "coral", "echo",
        "fable", "nova", "onyx", "sage", "shimmer",
    ]

    /// English voices first, then everything else, both alphabetized.
    static func appleVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            let lhsEnglish = $0.language.hasPrefix("en")
            let rhsEnglish = $1.language.hasPrefix("en")
            if lhsEnglish != rhsEnglish { return lhsEnglish }
            return ($0.language, $0.name) < ($1.language, $1.name)
        }
    }

    /// Short label for the player capsule, e.g. "Nova" or "Samantha".
    static func displayName(provider: TTSProvider, voice: String) -> String {
        switch provider {
        case .openAI:
            return voice.isEmpty ? "Alloy" : voice.capitalized
        case .apple:
            guard !voice.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voice) else {
                return "Default"
            }
            // "Samantha (Enhanced)" → "Samantha"
            return v.name.components(separatedBy: " (").first ?? v.name
        }
    }
}
