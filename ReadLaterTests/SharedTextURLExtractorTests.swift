import XCTest
@testable import ReadLater

final class SharedTextURLExtractorTests: XCTestCase {
    func testExtractsHTTPSURLFromTitlePlusLinkPayload() {
        // The Medium-style payload: article title followed by the link.
        let text = "The Case for Reading Later https://medium.com/@author/the-case-abc123"
        let url = SharedTextURLExtractor.firstURL(in: text)
        XCTAssertEqual(url?.absoluteString, "https://medium.com/@author/the-case-abc123")
    }

    func testReturnsFirstURLWhenSeveralPresent() {
        let text = "See https://example.com/first and also https://example.com/second"
        XCTAssertEqual(
            SharedTextURLExtractor.firstURL(in: text)?.absoluteString,
            "https://example.com/first"
        )
    }

    func testRecognisesBareHostWithoutScheme() {
        let url = SharedTextURLExtractor.firstURL(in: "check out medium.com today")
        XCTAssertEqual(url?.host, "medium.com")
        XCTAssertEqual(url?.scheme, "http")
    }

    func testAcceptsPlainURLOnly() {
        let url = SharedTextURLExtractor.firstURL(in: "https://example.com/path?q=1")
        XCTAssertEqual(url?.absoluteString, "https://example.com/path?q=1")
    }

    func testReturnsNilForTextWithNoLink() {
        XCTAssertNil(SharedTextURLExtractor.firstURL(in: "just some words, nothing to save"))
    }

    func testReturnsNilForEmptyText() {
        XCTAssertNil(SharedTextURLExtractor.firstURL(in: ""))
    }

    func testIgnoresNonWebSchemeLinks() {
        // NSDataDetector matches mailto: as a link; we only save web pages, so
        // the scheme filter must drop it.
        XCTAssertNil(SharedTextURLExtractor.firstURL(in: "write to mailto:hi@example.com"))
    }

    func testSkipsNonWebSchemeButKeepsFollowingWebURL() {
        let url = SharedTextURLExtractor.firstURL(in: "mailto:hi@example.com then https://example.com/read")
        XCTAssertEqual(url?.absoluteString, "https://example.com/read")
    }
}
