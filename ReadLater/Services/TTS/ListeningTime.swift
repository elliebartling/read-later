import Foundation

/// Estimates how long spoken playback of article text will take. TTS engines
/// don't report durations up front (OpenAI audio arrives lazily; Apple speaks
/// live), so both the reader subtitle and Now Playing info use a word-count
/// heuristic instead.
enum ListeningTime {
    /// Typical TTS speaking pace at 1x. Human narration averages 150–180 wpm;
    /// synthesized voices sit at the top of that range.
    static let wordsPerMinute: Double = 180

    static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Estimated seconds to speak `paragraphs[fromIndex...]` at `rate`.
    static func remainingSeconds(paragraphs: [String], fromIndex: Int, rate: Double) -> TimeInterval {
        guard rate > 0, fromIndex < paragraphs.count else { return 0 }
        let words = paragraphs[max(0, fromIndex)...].reduce(0) { $0 + wordCount(in: $1) }
        return Double(words) / wordsPerMinute * 60 / rate
    }

    /// Estimated seconds to speak all of `paragraphs` at `rate`.
    static func totalSeconds(paragraphs: [String], rate: Double) -> TimeInterval {
        remainingSeconds(paragraphs: paragraphs, fromIndex: 0, rate: rate)
    }

    /// "12 min left" / "1 min left" / "Less than a minute left".
    static func remainingLabel(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "Less than a minute left" }
        return "\(minutes) min left"
    }
}
