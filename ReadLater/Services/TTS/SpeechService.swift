import Foundation

/// Common interface both TTS backends implement so the reader UI doesn't care
/// which engine is playing.
@MainActor
protocol SpeechService: AnyObject {
    var delegate: SpeechServiceDelegate? { get set }
    var isPlaying: Bool { get }
    /// Whether the engine can change playback speed mid-paragraph without a
    /// restart. When false, TTSController restarts the current paragraph to
    /// apply a new rate.
    var supportsLiveRateChange: Bool { get }

    /// Enqueues `paragraphs` in order. `startAt` skips forward N paragraphs.
    /// `rate` is a speed multiplier (1.0 = normal). Engines kick off their own
    /// async work internally; this returns immediately.
    func play(paragraphs: [String], voice: String, rate: Double, startAt: Int)
    func pause()
    func resume()
    func stop()
    /// Applies a new speed to in-flight playback. Only meaningful when
    /// `supportsLiveRateChange` is true.
    func setRate(_ rate: Double)
}

@MainActor
protocol SpeechServiceDelegate: AnyObject {
    func speechService(_ service: SpeechService, didAdvanceTo paragraphIndex: Int)
    /// First audible output is ready (OpenAI after synthesis; Apple at utterance start).
    func speechServiceDidBeginPlayback(_ service: SpeechService)
    /// `errorMessage` is non-nil when playback ended because of a failure the
    /// user should see (missing API key, HTTP error) — not on normal finish
    /// or user-initiated stop.
    func speechService(_ service: SpeechService, didFinish successfully: Bool, errorMessage: String?)
}
