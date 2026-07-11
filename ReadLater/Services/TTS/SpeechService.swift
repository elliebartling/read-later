import Foundation

/// Common interface both TTS backends implement so the reader UI doesn't care
/// which engine is playing.
@MainActor
protocol SpeechService: AnyObject {
    var delegate: SpeechServiceDelegate? { get set }
    var isPlaying: Bool { get }
    var supportsPause: Bool { get }

    /// Enqueues `paragraphs` in order. `startAt` skips forward N paragraphs.
    func play(paragraphs: [String], voice: String, startAt: Int) async
    func pause()
    func resume()
    func stop()
}

@MainActor
protocol SpeechServiceDelegate: AnyObject {
    func speechService(_ service: SpeechService, didAdvanceTo paragraphIndex: Int)
    func speechService(_ service: SpeechService, didFinish successfully: Bool)
}
