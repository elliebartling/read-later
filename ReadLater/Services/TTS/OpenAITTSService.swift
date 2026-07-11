import Foundation
import AVFoundation

/// OpenAI text-to-speech backend.
///
/// This is paragraph-level pipelining, not true HTTP byte streaming:
///
/// - `play(...)` returns immediately after enqueuing work — the network call
///   does NOT block the UI.
/// - Up to `lookahead` paragraphs are synthesized concurrently. Each synthesis
///   task awaits its predecessor's `AVPlayerItem` append before appending its
///   own, so playback order is preserved even though HTTP requests are in
///   flight in parallel.
/// - As each paragraph finishes playing, the next lookahead is kicked off, so
///   the queue never drains during a continuous read.
///
/// Time-to-first-audio ≈ one paragraph's synthesis latency (~600ms–1.2s for
/// gpt-4o-mini-tts on a short paragraph). For faster time-to-first-audio, see
/// the "true HTTP streaming" note in README.md — that path swaps AVQueuePlayer
/// for AVAudioEngine + scheduled PCM buffers and is a chunkier change.
@MainActor
final class OpenAITTSService: NSObject, SpeechService {

    weak var delegate: SpeechServiceDelegate?

    private let player = AVQueuePlayer()
    private var paragraphs: [String] = []
    private var currentIndex: Int = 0
    private var currentVoice: String = "alloy"
    private var currentRate: Double = 1.0
    private var enqueuedThrough: Int = -1
    private var previousSynthTask: Task<Void, Never>?
    private var isRunning: Bool = false
    private var wantsPlayback = false
    private var hasSignaledPlaybackStart = false
    private var tempFiles: [URL] = []

    /// Number of paragraphs synthesized ahead of the currently-playing one.
    /// 2 keeps latency low without prefetching aggressively enough to burn
    /// OpenAI spend on paragraphs the user might skip past.
    private let lookahead = 2

    var isPlaying: Bool { player.timeControlStatus == .playing }
    /// AVQueuePlayer retimes mp3 audio on the fly (pitch-corrected via
    /// .timeDomain), so speed changes apply without a restart.
    var supportsLiveRateChange: Bool { true }

    override init() {
        super.init()
        configureAudioSession()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("OpenAI TTS audio session: %@", String(describing: error))
        }
    }

    // MARK: - SpeechService

    func play(paragraphs: [String], voice: String, rate: Double, startAt: Int = 0) {
        stop()
        guard let key = KeychainStore.get(account: KeychainStore.Account.openAI), !key.isEmpty else {
            delegate?.speechService(self, didFinish: false, errorMessage: ServiceError.noAPIKey.description)
            return
        }
        _ = key // just gating on presence

        self.paragraphs = paragraphs
        self.currentIndex = max(0, min(startAt, paragraphs.count - 1))
        self.currentVoice = voice.isEmpty ? "alloy" : voice
        self.currentRate = rate
        self.enqueuedThrough = self.currentIndex - 1
        self.isRunning = true
        self.wantsPlayback = true
        self.hasSignaledPlaybackStart = false
        delegate?.speechService(self, didAdvanceTo: currentIndex)
        pipelineNext()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
    }

    func resume() {
        wantsPlayback = true
        startPlaybackIfReady()
    }

    func setRate(_ rate: Double) {
        currentRate = rate
        if wantsPlayback, player.timeControlStatus == .playing {
            player.rate = Float(rate)
        }
    }

    func stop() {
        wantsPlayback = false
        hasSignaledPlaybackStart = false
        player.pause()
        player.removeAllItems()
        paragraphs = []
        currentIndex = 0
        enqueuedThrough = -1
        previousSynthTask?.cancel()
        previousSynthTask = nil
        isRunning = false
        cleanupTempFiles()
    }

    /// Starts the queue only when the user wants playback and audio is ready.
    private func startPlaybackIfReady() {
        guard wantsPlayback, isRunning, !player.items().isEmpty else { return }
        player.playImmediately(atRate: Float(currentRate))
        if !hasSignaledPlaybackStart {
            hasSignaledPlaybackStart = true
            delegate?.speechServiceDidBeginPlayback(self)
        }
    }

    // MARK: - Pipeline

    /// Reserves the next `lookahead` paragraph slots and kicks off concurrent
    /// synthesis for each. Each task waits for its immediate predecessor to
    /// finish appending before it appends, preserving playback order.
    private func pipelineNext() {
        while isRunning,
              enqueuedThrough - currentIndex + 1 < lookahead,
              enqueuedThrough + 1 < paragraphs.count
        {
            enqueuedThrough += 1
            let idx = enqueuedThrough
            let predecessor = previousSynthTask

            let task = Task { [weak self] in
                guard let self else { return }
                let text = self.paragraphs[safe: idx] ?? ""
                guard !text.isEmpty else { return }

                let data: Data
                do {
                    data = try await self.synthesize(text: text)
                } catch {
                    NSLog("OpenAI TTS synth failed on paragraph %d: %@", idx, String(describing: error))
                    let message = (error as? ServiceError)?.description ?? error.localizedDescription
                    self.delegate?.speechService(self, didFinish: false, errorMessage: message)
                    self.stop()
                    return
                }

                // Preserve queue order: wait until the previous paragraph has
                // been appended (or failed) before appending this one.
                await predecessor?.value

                guard self.isRunning else { return }
                guard let url = try? self.writeTempAudio(data: data, index: idx) else { return }
                self.tempFiles.append(url)
                let item = AVPlayerItem(url: url)
                item.audioTimePitchAlgorithm = .timeDomain
                self.player.insert(item, after: nil)
                self.startPlaybackIfReady()
            }
            previousSynthTask = task
        }
    }

    @objc private func itemDidFinish(_ note: Notification) {
        Task { @MainActor in
            guard isRunning else { return }
            currentIndex += 1
            if currentIndex >= paragraphs.count {
                delegate?.speechService(self, didFinish: true, errorMessage: nil)
                stop()
                return
            }
            delegate?.speechService(self, didAdvanceTo: currentIndex)
            pipelineNext()
        }
    }

    // MARK: - Network

    private func synthesize(text: String) async throws -> Data {
        guard let key = KeychainStore.get(account: KeychainStore.Account.openAI), !key.isEmpty else {
            throw ServiceError.noAPIKey
        }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "voice": currentVoice,
            "input": text,
            "response_format": "mp3",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.apiError(status: http.statusCode, body: msg)
        }
        return data
    }

    private func writeTempAudio(data: Data, index: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("chunk-\(index)-\(UUID().uuidString).mp3")
        try data.write(to: file, options: .atomic)
        return file
    }

    private func cleanupTempFiles() {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
    }

    enum ServiceError: Error, CustomStringConvertible {
        case noAPIKey
        case badResponse(Int)
        case apiError(status: Int, body: String)

        var description: String {
            switch self {
            case .noAPIKey: return "No OpenAI API key on file. Add one in Settings."
            case .badResponse(let s): return "Malformed response (\(s))."
            case .apiError(let s, let body): return "OpenAI \(s): \(body.prefix(240))"
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
