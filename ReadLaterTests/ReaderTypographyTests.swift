import XCTest
@testable import ReadLater

final class ReaderTypographyTests: XCTestCase {

    // MARK: ReaderWidth

    func testReaderWidthRawFallback() {
        let s = AppSettings()
        s.readerWidthRaw = "bogus"
        XCTAssertEqual(s.readerWidth, .medium)
    }

    func testReaderWidthInsetsOrdering() {
        // Narrower column = larger horizontal inset.
        XCTAssertGreaterThan(ReaderWidth.narrow.horizontalInset, ReaderWidth.medium.horizontalInset)
        XCTAssertGreaterThan(ReaderWidth.medium.horizontalInset, ReaderWidth.wide.horizontalInset)
        XCTAssertGreaterThan(ReaderWidth.wide.horizontalInset, ReaderWidth.full.horizontalInset)
    }

    func testAppSettingsSpacingDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.readerLineSpacing, 6, accuracy: 0.001)
        XCTAssertEqual(s.readerParagraphSpacing, 12, accuracy: 0.001)
        XCTAssertEqual(s.readerWidth, .medium)
    }

    func testAppSettingsWidthAccessorRoundTrips() {
        let s = AppSettings()
        s.readerWidth = .wide
        XCTAssertEqual(s.readerWidthRaw, "wide")
        XCTAssertEqual(s.readerWidth, .wide)
    }
}
