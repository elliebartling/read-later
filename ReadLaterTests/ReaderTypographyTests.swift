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

extension ReaderTypographyTests {
    func testReaderThemeRawFallback() {
        let s = AppSettings()
        s.readerThemeRaw = "bogus"
        XCTAssertEqual(s.readerTheme, .system)
    }

    func testAllThemesHaveOpaqueColors() {
        for theme in ReaderTheme.allCases {
            var alpha: CGFloat = 0
            theme.background.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1, accuracy: 0.001, "\(theme) background must be opaque")
        }
    }

    func testExplicitThemeDarkness() {
        XCTAssertTrue(ReaderTheme.dark.isDarkBackground(for: nil))
        XCTAssertTrue(ReaderTheme.slate.isDarkBackground(for: nil))
        XCTAssertTrue(ReaderTheme.forest.isDarkBackground(for: nil))
        XCTAssertTrue(ReaderTheme.darkGray.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.light.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.sepia.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.paper.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.mediumGray.isDarkBackground(for: nil))
    }

    func testNewThemeCasesExist() {
        let raws = Set(ReaderTheme.allCases.map(\.rawValue))
        for expected in ["darkGray", "mediumGray", "slate", "paper", "forest"] {
            XCTAssertTrue(raws.contains(expected), "missing theme \(expected)")
        }
    }
}
