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
    func testAllThemesHaveOpaqueColors() {
        for theme in ReaderTheme.allCases {
            var alpha: CGFloat = 0
            theme.background.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1, accuracy: 0.001, "\(theme) background must be opaque")
        }
    }

    func testExplicitThemeDarkness() {
        XCTAssertTrue(ReaderTheme.dark.isDark)
        XCTAssertTrue(ReaderTheme.slate.isDark)
        XCTAssertTrue(ReaderTheme.forest.isDark)
        XCTAssertTrue(ReaderTheme.darkGray.isDark)
        XCTAssertFalse(ReaderTheme.light.isDark)
        XCTAssertFalse(ReaderTheme.sepia.isDark)
        XCTAssertFalse(ReaderTheme.paper.isDark)
        XCTAssertFalse(ReaderTheme.mediumGray.isDark)
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

extension ReaderTypographyTests {
    func testReaderFontRawFallback() {
        XCTAssertEqual(ReaderFont(rawValue: "Bogus") ?? .serif, .serif)
    }

    func testEveryFontResolvesToAFont() {
        for font in ReaderFont.allCases {
            XCTAssertGreaterThan(font.uiFont(size: 18).pointSize, 0)
        }
    }

    func testFontGroupsCoverAllCases() {
        for font in ReaderFont.allCases {
            XCTAssertFalse(font.group.title.isEmpty)
        }
    }
}

extension ReaderTypographyTests {
    func testReaderAppearanceRawFallback() {
        let s = AppSettings()
        s.readerAppearanceRaw = "bogus"
        XCTAssertEqual(s.readerAppearance, .system)
    }

    func testPaletteMembership() {
        XCTAssertEqual(ReaderTheme.lightCases, [.light, .sepia, .paper, .mediumGray])
        XCTAssertEqual(ReaderTheme.darkCases, [.dark, .darkGray, .slate, .forest])
        for t in ReaderTheme.lightCases { XCTAssertFalse(t.isDark, "\(t) should be light") }
        for t in ReaderTheme.darkCases { XCTAssertTrue(t.isDark, "\(t) should be dark") }
    }

    func testPaletteAccessorsRejectWrongSide() {
        let s = AppSettings()
        s.readerLightThemeRaw = ReaderTheme.slate.rawValue   // dark palette in light slot
        XCTAssertEqual(s.readerLightTheme, .light)
        s.readerDarkThemeRaw = ReaderTheme.sepia.rawValue    // light palette in dark slot
        XCTAssertEqual(s.readerDarkTheme, .dark)
    }

    func testResolutionTruthTable() {
        let s = AppSettings()
        s.readerLightTheme = .paper
        s.readerDarkTheme = .slate

        s.readerAppearance = .light
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: false), .paper)
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: true), .paper)

        s.readerAppearance = .dark
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: false), .slate)
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: true), .slate)

        s.readerAppearance = .system
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: false), .paper)
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: true), .slate)
    }

    func testMigrationFromLegacyTheme() {
        // Light palette → light appearance carrying that palette.
        let a = AppSettings()
        a.readerThemeRaw = "sepia"
        a.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(a.readerAppearance, .light)
        XCTAssertEqual(a.readerLightTheme, .sepia)
        XCTAssertEqual(a.readerDarkTheme, .dark)

        // Dark palette → dark appearance carrying that palette.
        let b = AppSettings()
        b.readerThemeRaw = "slate"
        b.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(b.readerAppearance, .dark)
        XCTAssertEqual(b.readerDarkTheme, .slate)
        XCTAssertEqual(b.readerLightTheme, .light)

        // "system" and unknown → system + defaults.
        let c = AppSettings()
        c.readerThemeRaw = "system"
        c.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(c.readerAppearance, .system)

        let d = AppSettings()
        d.readerThemeRaw = "bogus"
        d.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(d.readerAppearance, .system)

        // Idempotent: second run doesn't clobber a user change.
        a.readerLightTheme = .paper
        a.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(a.readerLightTheme, .paper)
    }
}
