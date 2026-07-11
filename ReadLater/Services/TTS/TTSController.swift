import Foundation
import Observation

/// Front-of-house TTS coordinator that Reader UI observes. Picks the backend
/// based on AppSettings.ttsProvider, forwards paragraph-advance events so the
/// reader can highlight the currently-spoken paragraph, and mirrors playback
/// state to the lock screen (Now Playing + remote commands).
@Observable
@MainActor
final class TTSController {

    enum PlaybackState {
        case idle
        case playing
        case paused
    }

    private(set) var state: PlaybackState = .idle
    private(set) var currentParagraph: Int = 0
    private(set) var totalParagraphs: Int = 0
    /// Speed multiplier (1.0 = normal). Reflected live into the engine.
    private(set) var rate: Double = 1.0
    /// Voice identifier for the active provider.
    private(set) var voice: String = ""
    /// User-visible failure from the active backend (missing API key, HTTP
    /// error). The reader presents this in an alert; assign nil to dismiss.
    var lastError: String?

    var isPlaying: Bool { state == .playing }
    /// True while the player UI (capsule) should be visible.
    var isActive: Bool { state != .idle }

    /// 0...1 fraction of paragraphs completed.
    var progress: Double {
        guard totalParagraphs > 0 else { return 0 }
        return Double(currentParagraph) / Double(totalParagraphs)
    }

    /// Estimated seconds of speech left at the current rate.
    var remainingSeconds: TimeInterval {
        ListeningTime.remainingSeconds(paragraphs: paragraphs, fromIndex: currentParagraph, rate: rate)
    }

    private var paragraphs: [String] = []
    private var provider: TTSProvider = .apple
    private var nowPlayingTitle: String = ""
    private var nowPlayingArtist: String?

    private var service: SpeechService?
    private var delegateHolder: DelegateHolder?
    private let nowPlaying = NowPlayingManager()

    // MARK: - Lifecycle

    func start(
        paragraphs: [String],
        provider: TTSProvider,
        voice: String,
        rate: Double,
        title: String,
        artist: String? = nil,
        startAt: Int = 0
    ) {
        teardownService()
        lastError = nil
        self.paragraphs = paragraphs
        self.provider = provider
        self.voice = voice
        self.rate = rate
        self.nowPlayingTitle = title
        self.nowPlayingArtist = artist
        totalParagraphs = paragraphs.count
        currentParagraph = min(max(0, startAt), max(0, paragraphs.count - 1))
        state = .playing
        nowPlaying.activate(controller: self)
        playCurrentService(startAt: currentParagraph)
    }

    func pause() {
        guard state == .playing else { return }
        service?.pause()
        state = .paused
        refreshNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        service?.resume()
        state = .playing
        refreshNowPlaying()
    }

    /// Toggles between playing and paused. No-op when idle — the reader
    /// starts playback explicitly via `start` so it can pass fresh settings.
    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .idle: break
        }
    }

    /// Ends playback and collapses the player UI, but remembers the paragraph
    /// so the next `start(startAt: controller.currentParagraph)` resumes
    /// where the user left off.
    func stop() {
        teardownService()
        state = .idle
        totalParagraphs = 0
        nowPlaying.deactivate()
    }

    // MARK: - Adjustments

    /// Switches voice mid-article by restarting the current paragraph.
    func setVoice(_ newVoice: String) {
        guard newVoice != voice else { return }
        voice = newVoice
        restartCurrentParagraphIfActive()
    }

    /// Changes speed. Applied live when the engine supports it, otherwise the
    /// current paragraph restarts at the new speed.
    func setRate(_ newRate: Double) {
        guard newRate != rate, newRate > 0 else { return }
        rate = newRate
        guard let service, isActive else { return }
        if service.supportsLiveRateChange {
            service.setRate(newRate)
            refreshNowPlaying()
        } else {
            restartCurrentParagraphIfActive()
        }
    }

    func skipForward() {
        guard isActive, currentParagraph + 1 < totalParagraphs else { return }
        seek(to: currentParagraph + 1)
    }

    func skipBackward() {
        guard isActive else { return }
        seek(to: max(0, currentParagraph - 1))
    }

    private func seek(to index: Int) {
        guard isActive, !paragraphs.isEmpty else { return }
        currentParagraph = min(max(0, index), paragraphs.count - 1)
        let wasPaused = state == .paused
        playCurrentService(startAt: currentParagraph)
        state = .playing
        if wasPaused {
            // Preserve the paused state across the restart.
            service?.pause()
            state = .paused
        }
        refreshNowPlaying()
    }

    // MARK: - Engine plumbing

    /// Test seam: overrides engine construction so unit tests can observe
    /// playback calls without touching AVFoundation.
    @ObservationIgnored
    var serviceFactory: ((TTSProvider) -> SpeechService)?

    private func makeService() -> SpeechService {
        if let serviceFactory {
            return serviceFactory(provider)
        }
        switch provider {
        case .apple: return AppleSpeechService()
        case .openAI: return OpenAITTSService()
        }
    }

    private func playCurrentService(startAt: Int) {
        let service = self.service ?? makeService()
        if delegateHolder == nil {
            delegateHolder = DelegateHolder(owner: self)
        }
        service.delegate = delegateHolder
        self.service = service
        service.play(paragraphs: paragraphs, voice: voice, rate: rate, startAt: startAt)
        refreshNowPlaying()
    }

    private func restartCurrentParagraphIfActive() {
        guard isActive, !paragraphs.isEmpty else { return }
        seek(to: currentParagraph)
    }

    private func teardownService() {
        service?.stop()
        service = nil
        delegateHolder = nil
    }

    private func refreshNowPlaying() {
        guard isActive else { return }
        let total = ListeningTime.totalSeconds(paragraphs: paragraphs, rate: rate)
        nowPlaying.update(
            title: nowPlayingTitle,
            artist: nowPlayingArtist,
            elapsed: max(0, total - remainingSeconds),
            duration: total,
            playbackRate: state == .playing ? rate : 0
        )
    }

    // Kept out of the @Observable surface so it doesn't spam view updates.
    @MainActor
    private final class DelegateHolder: SpeechServiceDelegate {
        weak var owner: TTSController?
        init(owner: TTSController) { self.owner = owner }

        func speechService(_ service: SpeechService, didAdvanceTo paragraphIndex: Int) {
            guard let owner else { return }
            owner.currentParagraph = paragraphIndex
            owner.refreshNowPlaying()
        }

        func speechService(_ service: SpeechService, didFinish successfully: Bool, errorMessage: String?) {
            guard let owner else { return }
            if let errorMessage {
                owner.lastError = errorMessage
            }
            if successfully {
                // Natural finish: next play starts from the top.
                owner.currentParagraph = 0
            }
            owner.stop()
        }
    }
}
