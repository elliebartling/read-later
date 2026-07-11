import XCTest
@testable import ReadLater

/// Records SpeechService calls so TTSController's state machine can be tested
/// without AVFoundation.
@MainActor
private final class FakeSpeechService: SpeechService {
    weak var delegate: SpeechServiceDelegate?
    var isPlaying = false
    var supportsLiveRateChange: Bool

    struct PlayCall: Equatable {
        let paragraphCount: Int
        let voice: String
        let rate: Double
        let startAt: Int
    }

    private(set) var playCalls: [PlayCall] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var setRateCalls: [Double] = []

    init(supportsLiveRateChange: Bool = true) {
        self.supportsLiveRateChange = supportsLiveRateChange
    }

    func play(paragraphs: [String], voice: String, rate: Double, startAt: Int) {
        playCalls.append(PlayCall(paragraphCount: paragraphs.count, voice: voice, rate: rate, startAt: startAt))
        isPlaying = true
    }

    func pause() {
        pauseCount += 1
        isPlaying = false
    }

    func resume() {
        resumeCount += 1
        isPlaying = true
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }

    func setRate(_ rate: Double) {
        setRateCalls.append(rate)
    }

    // Test helpers to drive delegate callbacks like a real engine would.
    func advance(to index: Int) {
        delegate?.speechService(self, didAdvanceTo: index)
    }

    func finish(successfully: Bool, errorMessage: String? = nil) {
        delegate?.speechService(self, didFinish: successfully, errorMessage: errorMessage)
    }
}

@MainActor
final class TTSControllerTests: XCTestCase {

    private var fake: FakeSpeechService!
    private var controller: TTSController!

    override func setUp() async throws {
        fake = FakeSpeechService()
        controller = TTSController()
        controller.serviceFactory = { [fake] _ in fake! }
    }

    private func start(paragraphs: [String] = ["one two", "three four", "five six"],
                       rate: Double = 1.0,
                       startAt: Int = 0)
    {
        controller.start(
            paragraphs: paragraphs,
            provider: .apple,
            voice: "test-voice",
            rate: rate,
            title: "Test Article",
            startAt: startAt
        )
    }

    func testStartEntersPlayingAndForwardsConfig() {
        start(rate: 1.5)
        XCTAssertEqual(controller.state, .playing)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.totalParagraphs, 3)
        XCTAssertEqual(controller.currentParagraph, 0)
        XCTAssertEqual(fake.playCalls, [.init(paragraphCount: 3, voice: "test-voice", rate: 1.5, startAt: 0)])
    }

    func testStartClampsStartIndex() {
        start(startAt: 99)
        XCTAssertEqual(controller.currentParagraph, 2)
        XCTAssertEqual(fake.playCalls.last?.startAt, 2)
    }

    func testPauseAndResume() {
        start()
        controller.pause()
        XCTAssertEqual(controller.state, .paused)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(fake.pauseCount, 1)

        controller.resume()
        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(fake.resumeCount, 1)
    }

    func testPauseIgnoredWhenIdle() {
        controller.pause()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(fake.pauseCount, 0)
    }

    func testTogglePlayPause() {
        start()
        controller.togglePlayPause()
        XCTAssertEqual(controller.state, .paused)
        controller.togglePlayPause()
        XCTAssertEqual(controller.state, .playing)
    }

    func testStopRemembersPositionForResume() {
        start()
        fake.advance(to: 2)
        XCTAssertEqual(controller.currentParagraph, 2)

        controller.stop()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isActive)
        // Position survives so the reader can pass startAt:
        // controller.currentParagraph on the next start.
        XCTAssertEqual(controller.currentParagraph, 2)

        start(startAt: controller.currentParagraph)
        XCTAssertEqual(fake.playCalls.last?.startAt, 2)
    }

    func testNaturalFinishResetsPosition() {
        start()
        fake.advance(to: 2)
        fake.finish(successfully: true)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.currentParagraph, 0)
        XCTAssertNil(controller.lastError)
    }

    func testFailureSurfacesError() {
        start()
        fake.finish(successfully: false, errorMessage: "No API key")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.lastError, "No API key")
    }

    func testSkipForwardRestartsAtNextParagraph() {
        start()
        fake.advance(to: 1)
        controller.skipForward()
        XCTAssertEqual(controller.currentParagraph, 2)
        XCTAssertEqual(fake.playCalls.last?.startAt, 2)
        XCTAssertEqual(controller.state, .playing)
    }

    func testSkipForwardStopsAtLastParagraph() {
        start()
        fake.advance(to: 2)
        let callsBefore = fake.playCalls.count
        controller.skipForward()
        XCTAssertEqual(controller.currentParagraph, 2)
        XCTAssertEqual(fake.playCalls.count, callsBefore)
    }

    func testSkipBackwardClampsToZero() {
        start()
        controller.skipBackward()
        XCTAssertEqual(controller.currentParagraph, 0)
        XCTAssertEqual(fake.playCalls.last?.startAt, 0)
    }

    func testSkipWhilePausedStaysPaused() {
        start()
        fake.advance(to: 1)
        controller.pause()
        controller.skipForward()
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(controller.currentParagraph, 2)
        // Restarted at the new paragraph, then immediately re-paused.
        XCTAssertEqual(fake.playCalls.last?.startAt, 2)
        XCTAssertEqual(fake.pauseCount, 2)
    }

    func testSetRateLiveWhenEngineSupportsIt() {
        start()
        let callsBefore = fake.playCalls.count
        controller.setRate(2.0)
        XCTAssertEqual(controller.rate, 2.0)
        XCTAssertEqual(fake.setRateCalls, [2.0])
        // No paragraph restart needed.
        XCTAssertEqual(fake.playCalls.count, callsBefore)
    }

    func testSetRateRestartsParagraphWhenEngineCannotRetime() {
        fake = FakeSpeechService(supportsLiveRateChange: false)
        controller.serviceFactory = { [fake] _ in fake! }
        start()
        fake.advance(to: 1)
        controller.setRate(1.5)
        XCTAssertEqual(controller.rate, 1.5)
        XCTAssertTrue(fake.setRateCalls.isEmpty)
        XCTAssertEqual(fake.playCalls.last, .init(paragraphCount: 3, voice: "test-voice", rate: 1.5, startAt: 1))
    }

    func testSetRateIgnoredWhenIdleOrInvalid() {
        controller.setRate(1.5)
        XCTAssertEqual(controller.rate, 1.5) // stored for the next start…
        XCTAssertTrue(fake.playCalls.isEmpty) // …but nothing restarts.

        start(rate: 1.5)
        controller.setRate(0)
        XCTAssertEqual(controller.rate, 1.5)
    }

    func testSetVoiceRestartsCurrentParagraph() {
        start()
        fake.advance(to: 1)
        controller.setVoice("new-voice")
        XCTAssertEqual(controller.voice, "new-voice")
        XCTAssertEqual(fake.playCalls.last, .init(paragraphCount: 3, voice: "new-voice", rate: 1.0, startAt: 1))
        XCTAssertEqual(controller.state, .playing)
    }

    func testSetSameVoiceDoesNothing() {
        start()
        let callsBefore = fake.playCalls.count
        controller.setVoice("test-voice")
        XCTAssertEqual(fake.playCalls.count, callsBefore)
    }

    func testProgressFraction() {
        start()
        XCTAssertEqual(controller.progress, 0, accuracy: 0.001)
        fake.advance(to: 1)
        XCTAssertEqual(controller.progress, 1.0 / 3.0, accuracy: 0.001)
        controller.stop()
        XCTAssertEqual(controller.progress, 0, accuracy: 0.001)
    }
}
