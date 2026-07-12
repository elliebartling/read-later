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

extension ReaderTypographyTests {
    private func luminance(_ c: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    func testCompositedHighlightsAreOpaque() {
        for color in HighlightColor.allCases {
            for dark in [true, false] {
                var a: CGFloat = 0
                color.uiColor(darkBackground: dark).getRed(nil, green: nil, blue: nil, alpha: &a)
                XCTAssertEqual(a, 1, accuracy: 0.001)
            }
        }
    }

    func testLightAndDarkRecipesDiffer() {
        for color in HighlightColor.allCases {
            XCTAssertNotEqual(color.uiColor(darkBackground: false),
                              color.uiColor(darkBackground: true))
        }
    }

    func testDarkRecipeIsLighterThanDarkPage() {
        // On a dark page the band must be brighter than the page to stay legible.
        let darkPage = ReaderTheme.dark.background
        for color in HighlightColor.allCases {
            XCTAssertGreaterThan(luminance(color.uiColor(darkBackground: true)),
                                 luminance(darkPage))
        }
    }

    func testLightRecipeStaysBelowWhite() {
        for color in HighlightColor.allCases {
            XCTAssertLessThan(luminance(color.uiColor(darkBackground: false)), 1.0)
        }
    }
}
