import Foundation
import AVFoundation

/// OpenAI text-to-speech backend. Streams one paragraph at a time and enqueues
/// audio on an AVQueuePlayer so seek + resume feel snappy. Requires a user-
/// supplied API key stored in Keychain.
@MainActor
final class OpenAITTSService: NSObject, SpeechService {
    weak var delegate: SpeechServiceDelegate?
    private let player = AVQueuePlayer()
    private var queue: [String] = []
    private var currentIndex: Int = 0
    private var currentVoice: String = "alloy"
    private var isRunning = false
    private var playerObserver: NSKeyValueObservation?

    var isPlaying: Bool { player.timeControlStatus == .playing }
    var supportsPause: Bool { true }

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
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(paragraphs: [String], voice: String, startAt: Int = 0) async {
        stop()
        queue = paragraphs
        currentIndex = max(0, min(startAt, paragraphs.count - 1))
        currentVoice = voice.isEmpty ? "alloy" : voice
        isRunning = true

        // Prefetch the first two paragraphs to keep the queue warm.
        for lookahead in 0..<min(2, queue.count - currentIndex) {
            await enqueueParagraph(atOffset: lookahead)
        }
        player.play()
        delegate?.speechService(self, didAdvanceTo: currentIndex)
    }

    private func enqueueParagraph(atOffset offset: Int) async {
        let idx = currentIndex + offset
        guard idx < queue.count else { return }
        do {
            let data = try await synthesize(text: queue[idx])
            let url = try writeTempAudio(data: data, index: idx)
            let item = AVPlayerItem(url: url)
            player.insert(item, after: nil)
        } catch {
            NSLog("OpenAI TTS synth failed: %@", String(describing: error))
        }
    }

    @objc private func itemDidFinish(_ note: Notification) {
        Task { @MainActor in
            currentIndex += 1
            if currentIndex < queue.count {
                delegate?.speechService(self, didAdvanceTo: currentIndex)
                await enqueueParagraph(atOffset: 1) // keep two-deep
            } else {
                delegate?.speechService(self, didFinish: true)
                stop()
            }
        }
    }

    func pause() { player.pause() }
    func resume() { player.play() }

    func stop() {
        player.pause()
        player.removeAllItems()
        queue = []
        currentIndex = 0
        isRunning = false
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
        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "voice": currentVoice,
            "input": text,
            "response_format": "mp3",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
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

    enum ServiceError: Error {
        case noAPIKey
        case badResponse(Int)
    }
}
