import Foundation
import Observation

/// Front-of-house TTS coordinator that Reader UI observes. Picks the backend
/// based on AppSettings.ttsProvider and forwards paragraph-advance events so
/// the reader can highlight the currently-spoken paragraph.
@Observable
@MainActor
final class TTSController {
    private(set) var isPlaying: Bool = false
    private(set) var currentParagraph: Int = 0
    private(set) var totalParagraphs: Int = 0

    private var service: SpeechService?
    private var delegateHolder: DelegateHolder?

    func start(paragraphs: [String], provider: TTSProvider, voice: String, startAt: Int = 0) {
        stop()
        let service: SpeechService = {
            switch provider {
            case .apple: return AppleSpeechService()
            case .openAI: return OpenAITTSService()
            }
        }()
        let holder = DelegateHolder(owner: self)
        service.delegate = holder
        self.service = service
        self.delegateHolder = holder
        totalParagraphs = paragraphs.count
        currentParagraph = startAt
        isPlaying = true
        Task { await service.play(paragraphs: paragraphs, voice: voice, startAt: startAt) }
    }

    func pause() {
        service?.pause()
        isPlaying = false
    }

    func resume() {
        service?.resume()
        isPlaying = true
    }

    func stop() {
        service?.stop()
        service = nil
        delegateHolder = nil
        isPlaying = false
        currentParagraph = 0
    }

    // Kept out of the @Observable surface so it doesn't spam view updates.
    @MainActor
    private final class DelegateHolder: SpeechServiceDelegate {
        weak var owner: TTSController?
        init(owner: TTSController) { self.owner = owner }

        func speechService(_ service: SpeechService, didAdvanceTo paragraphIndex: Int) {
            owner?.currentParagraph = paragraphIndex
        }
        func speechService(_ service: SpeechService, didFinish successfully: Bool) {
            owner?.isPlaying = false
        }
    }
}
