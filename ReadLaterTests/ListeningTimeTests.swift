import XCTest
@testable import ReadLater

final class ListeningTimeTests: XCTestCase {

    func testWordCount() {
        XCTAssertEqual(ListeningTime.wordCount(in: ""), 0)
        XCTAssertEqual(ListeningTime.wordCount(in: "one"), 1)
        XCTAssertEqual(ListeningTime.wordCount(in: "one  two\nthree\tfour"), 4)
    }

    func testRemainingSecondsAtNormalRate() {
        // 180 words at 180 wpm = exactly one minute.
        let paragraph = Array(repeating: "word", count: 180).joined(separator: " ")
        let seconds = ListeningTime.remainingSeconds(paragraphs: [paragraph], fromIndex: 0, rate: 1.0)
        XCTAssertEqual(seconds, 60, accuracy: 0.001)
    }

    func testRemainingSecondsScalesWithRate() {
        let paragraph = Array(repeating: "word", count: 180).joined(separator: " ")
        let seconds = ListeningTime.remainingSeconds(paragraphs: [paragraph], fromIndex: 0, rate: 2.0)
        XCTAssertEqual(seconds, 30, accuracy: 0.001)
    }

    func testRemainingSecondsSkipsSpokenParagraphs() {
        let paragraph = Array(repeating: "word", count: 90).joined(separator: " ")
        let paragraphs = [paragraph, paragraph, paragraph]
        let all = ListeningTime.remainingSeconds(paragraphs: paragraphs, fromIndex: 0, rate: 1.0)
        let fromSecond = ListeningTime.remainingSeconds(paragraphs: paragraphs, fromIndex: 1, rate: 1.0)
        XCTAssertEqual(all, 90, accuracy: 0.001)
        XCTAssertEqual(fromSecond, 60, accuracy: 0.001)
    }

    func testRemainingSecondsPastEndIsZero() {
        XCTAssertEqual(ListeningTime.remainingSeconds(paragraphs: ["a b c"], fromIndex: 5, rate: 1.0), 0)
        XCTAssertEqual(ListeningTime.remainingSeconds(paragraphs: [], fromIndex: 0, rate: 1.0), 0)
    }

    func testRemainingLabel() {
        XCTAssertEqual(ListeningTime.remainingLabel(seconds: 10), "Less than a minute left")
        XCTAssertEqual(ListeningTime.remainingLabel(seconds: 60), "1 min left")
        XCTAssertEqual(ListeningTime.remainingLabel(seconds: 12 * 60), "12 min left")
        // 149s rounds to 2 minutes.
        XCTAssertEqual(ListeningTime.remainingLabel(seconds: 149), "2 min left")
    }

    func testSpeedLabelFormatting() {
        XCTAssertEqual(AudioPlayerBar.speedLabel(for: 1.0), "1x")
        XCTAssertEqual(AudioPlayerBar.speedLabel(for: 2.0), "2x")
        XCTAssertEqual(AudioPlayerBar.speedLabel(for: 1.25), "1.25x")
        XCTAssertEqual(AudioPlayerBar.speedLabel(for: 1.5), "1.5x")
        XCTAssertEqual(AudioPlayerBar.speedLabel(for: 0.75), "0.75x")
    }
}
