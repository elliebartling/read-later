import Foundation
import AVFoundation

@MainActor
final class AppleSpeechService: NSObject, SpeechService {
    weak var delegate: SpeechServiceDelegate?
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [String] = []
    private var currentIndex: Int = 0
    private var currentVoice: AVSpeechSynthesisVoice?

    var isPlaying: Bool { synthesizer.isSpeaking && !synthesizer.isPaused }
    var supportsPause: Bool { true }

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

    func play(paragraphs: [String], voice: String, startAt: Int = 0) async {
        stop()
        queue = paragraphs
        currentIndex = max(0, min(startAt, paragraphs.count - 1))
        currentVoice = AVSpeechSynthesisVoice(identifier: voice) ?? AVSpeechSynthesisVoice(language: "en-US")
        speakCurrent()
    }

    private func speakCurrent() {
        guard currentIndex < queue.count else {
            delegate?.speechService(self, didFinish: true)
            return
        }
        delegate?.speechService(self, didAdvanceTo: currentIndex)
        let utter = AVSpeechUtterance(string: queue[currentIndex])
        utter.voice = currentVoice
        utter.rate = AVSpeechUtteranceDefaultSpeechRate
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
}

extension AppleSpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.currentIndex += 1
            self.speakCurrent()
        }
    }
}
