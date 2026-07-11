import Foundation
import AVFoundation

@MainActor
final class AppleSpeechService: NSObject, SpeechService {
    weak var delegate: SpeechServiceDelegate?
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [String] = []
    private var currentIndex: Int = 0
    private var currentVoice: AVSpeechSynthesisVoice?
    private var currentRate: Double = 1.0

    var isPlaying: Bool { synthesizer.isSpeaking && !synthesizer.isPaused }
    /// AVSpeechSynthesizer can't retime an utterance that is already speaking;
    /// the controller restarts the current paragraph instead.
    var supportsLiveRateChange: Bool { false }

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("AVAudioSession: %@", String(describing: error))
        }
    }

    func play(paragraphs: [String], voice: String, rate: Double, startAt: Int = 0) {
        stop()
        queue = paragraphs
        currentIndex = max(0, min(startAt, paragraphs.count - 1))
        currentVoice = AVSpeechSynthesisVoice(identifier: voice) ?? AVSpeechSynthesisVoice(language: "en-US")
        currentRate = rate
        speakCurrent()
    }

    private func speakCurrent() {
        guard currentIndex < queue.count else {
            delegate?.speechService(self, didFinish: true, errorMessage: nil)
            return
        }
        delegate?.speechService(self, didAdvanceTo: currentIndex)
        let utter = AVSpeechUtterance(string: queue[currentIndex])
        utter.voice = currentVoice
        utter.rate = Self.utteranceRate(for: currentRate)
        synthesizer.speak(utter)
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        queue = []
        currentIndex = 0
    }

    func setRate(_ rate: Double) {
        // Takes effect on the next utterance; the controller handles the
        // restart-current-paragraph path for immediate changes.
        currentRate = rate
    }

    /// Maps a user-facing multiplier (0.75x…2x) onto AVSpeechUtterance's
    /// 0...1 rate scale, where the default (0.5) is "1x".
    static func utteranceRate(for multiplier: Double) -> Float {
        let base = AVSpeechUtteranceDefaultSpeechRate // 0.5
        let scaled = base * Float(multiplier)
        return min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, scaled))
    }
}

extension AppleSpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentIndex += 1
            self.speakCurrent()
        }
    }
}
