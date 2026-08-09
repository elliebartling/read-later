import XCTest
@testable import ReadLater

/// Issue #77 — the reader appearance sheet's tabs, and the B3 split.
///
/// A SwiftUI sheet's layout is checked by eye and by screenshot; what is worth
/// pinning here is the part that is *rules*, not pixels: which tabs exist and
/// in what order, that the sheet lands on the one B0 names, that the sheet and
/// the player capsule cannot drift to different speed steps, and that the
/// session/account split of read-aloud settings stays where §8.6 B3 puts it.
final class ReaderAppearanceSheetTests: XCTestCase {

    // MARK: - The tabs

    /// Ellen named three, in this order. A fourth tab is a design change, not
    /// a refactor.
    func testThreeTabsInEllensOrder() {
        XCTAssertEqual(
            ReaderAppearanceSheet.Tab.allCases.map(\.rawValue),
            ["Color", "Type", "Audio"]
        )
    }

    /// **B0** — prominence follows frequency, so the sheet opens on the tab
    /// that holds text size rather than on the leftmost one.
    func testLandsOnTheTabThatHoldsTextSize() {
        XCTAssertEqual(ReaderAppearanceSheet.landingTab, .type)
        XCTAssertNotEqual(
            ReaderAppearanceSheet.landingTab,
            ReaderAppearanceSheet.Tab.allCases[0],
            "If the landing tab ever becomes the leftmost one, text size stopped leading."
        )
    }

    /// T7 — sentence case everywhere, including the segment labels.
    func testTabLabelsAreSentenceCase() {
        for tab in ReaderAppearanceSheet.Tab.allCases {
            let rest = tab.rawValue.dropFirst()
            XCTAssertFalse(
                rest.contains(where: { $0.isUppercase }),
                "\(tab.rawValue) is Title Case"
            )
        }
    }

    // MARK: - Speed

    /// The Audio tab and the player capsule offer the same five speeds. Two
    /// controls for one value must not disagree about its legal values.
    func testSheetAndCapsuleOfferTheSameSpeeds() {
        XCTAssertEqual(
            ReaderAppearanceSheet.speedSteps.sorted(),
            AudioPlayerBar.speedSteps.sorted()
        )
    }

    /// A segmented picker can only show a selection for a tag it renders, so a
    /// stored rate that predates this list must snap to a step rather than
    /// leaving the control blank.
    func testStoredRateSnapsToTheNearestStep() {
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 1.0), 1.0)
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 0.75), 0.75)
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 2.0), 2.0)
        // Values no longer offered.
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 1.1), 1.0)
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 1.4), 1.5)
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 3.0), 2.0)
        XCTAssertEqual(ReaderAppearanceSheet.nearestSpeedStep(to: 0.1), 0.75)
    }

    // MARK: - B3, the session / account split

    /// Session-scope settings are the ones the Audio tab writes. They must
    /// round-trip through `AppSettings` for whichever provider is active, so
    /// the reader never edits the wrong stored property.
    func testVoiceWritesTheActiveProvidersField() {
        let settings = AppSettings()

        settings.ttsProvider = .apple
        settings.appleVoiceID = "com.apple.voice.compact.en-GB.Daniel"
        XCTAssertEqual(settings.openAIVoice, "alloy", "Apple's pick must not touch OpenAI's")

        settings.ttsProvider = .openAI
        settings.openAIVoice = "nova"
        XCTAssertEqual(
            settings.appleVoiceID, "com.apple.voice.compact.en-GB.Daniel",
            "OpenAI's pick must not touch Apple's"
        )
    }

    /// The account-scope settings stay in `AppSettings` untouched by this
    /// change — the split moved *where they are edited*, not where they live.
    func testProviderRemainsAnAccountLevelSetting() {
        let settings = AppSettings()
        XCTAssertEqual(settings.ttsProvider, .apple)
        settings.ttsProvider = .openAI
        XCTAssertEqual(settings.ttsProviderRaw, TTSProvider.openAI.rawValue)
    }

    // MARK: - The Type tab's content

    /// Every face in the catalogue gets a block. The old list grouped them
    /// under three headers; the grid drops the headers but must not drop a
    /// face with them.
    func testEveryFaceIsOfferedAsABlock() {
        XCTAssertEqual(ReaderFont.allCases.count, 11)
        XCTAssertEqual(Set(ReaderFont.allCases.map(\.rawValue)).count, 11)
    }

    /// The face grid renders `ReaderFont.allCases` in declaration order, which
    /// is what preserves the reading → accessibility → sans grouping now that
    /// the headers are gone (B6).
    func testFaceOrderStillGroupsByKind() {
        let groups = ReaderFont.allCases.map(\.group)
        XCTAssertEqual(groups, groups.sorted { a, b in
            let rank: (ReaderFont.Group) -> Int = {
                switch $0 {
                case .reading: return 0
                case .accessibility: return 1
                case .sans: return 2
                }
            }
            return rank(a) < rank(b)
        })
    }

    // MARK: - The warm paper spine (handed over from PR #82 §6)

    /// A paper with no hue of its own sits on the app's warm 72° spine, not on
    /// a grey of its own. The test is the spine's own shape: red leads blue,
    /// green sits between, and the whole thing stays under the chroma ceiling
    /// that would make it parchment (N4).
    func testNeutralPapersAreWarmNotCoolOrPure() {
        for theme in ReaderTheme.neutralCases {
            for (name, color) in [("paper", theme.background), ("ink", theme.foreground)] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
                let spread = (r - b) * 255
                XCTAssertGreaterThan(
                    spread, 0,
                    "\(theme.rawValue) \(name) is cool or pure neutral — it must be on the warm spine"
                )
                XCTAssertLessThanOrEqual(
                    spread, 8,
                    "\(theme.rawValue) \(name) is warm enough to read as parchment (N4)"
                )
                XCTAssertTrue(
                    (g - b) >= 0 && (r - g) >= 0,
                    "\(theme.rawValue) \(name) does not follow the ramp's R ≥ G ≥ B"
                )
            }
        }
    }

    /// The four papers whose hue is the point stay off the spine. This is the
    /// guard against a future "warm everything" sweep flattening the catalogue.
    func testHuedPapersAreLeftAlone() {
        XCTAssertEqual(
            Set(ReaderTheme.neutralCases).union(ReaderTheme.huedCases),
            Set(ReaderTheme.allCases)
        )
        XCTAssertTrue(Set(ReaderTheme.neutralCases).isDisjoint(with: ReaderTheme.huedCases))

        // Slate is navy and must stay navy: blue leads red.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(ReaderTheme.slate.background.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertGreaterThan(b, r)
    }

    /// The sweep's companion suggestion was to swap the default dark paper off
    /// Slate. It was never on Slate — pinned so the claim does not resurface.
    func testDefaultPapersAreTheNeutralOnes() {
        let settings = AppSettings()
        XCTAssertEqual(settings.readerDarkTheme, .dark)
        XCTAssertEqual(settings.readerLightTheme, .light)
        settings.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(settings.readerAppearance, .system)
        XCTAssertEqual(settings.resolvedReaderTheme(systemIsDark: true), .dark)
        XCTAssertEqual(settings.resolvedReaderTheme(systemIsDark: false), .light)
    }

    /// **The warming is a hue change, not a lightness change.** §4.1 protects
    /// the catalogue as finished work; the licence taken here was to put the
    /// hueless papers on the app's spine *at their existing lightness*, so no
    /// contrast figure moves and no paper changes place in the ramp. These are
    /// the pre-warming values, kept as the reference the change is measured
    /// against — a future edit that darkens or lightens one of these papers is
    /// a different decision and needs Ellen, not a refactor.
    func testWarmingPreservedEveryNeutralPapersLightness() {
        func luminance(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let before: [ReaderTheme: (paper: UIColor, ink: UIColor)] = [
            .light: (UIColor(white: 0.99, alpha: 1),
                     UIColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1)),
            .dark: (UIColor(white: 0.06, alpha: 1),
                    UIColor(white: 0.92, alpha: 1)),
            .darkGray: (UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1),
                        UIColor(white: 0.95, alpha: 1)),
            .mediumGray: (UIColor(red: 0.82, green: 0.82, blue: 0.839, alpha: 1),
                          UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)),
        ]
        for (theme, old) in before {
            XCTAssertEqual(
                luminance(theme.background), luminance(old.paper), accuracy: 0.01,
                "\(theme.rawValue) paper changed lightness, not just hue"
            )
            XCTAssertEqual(
                luminance(theme.foreground), luminance(old.ink), accuracy: 0.01,
                "\(theme.rawValue) ink changed lightness, not just hue"
            )
        }
    }

    /// Both theme palettes are offered, and a light palette never leaks into
    /// the dark grid (the Color tab renders these two arrays directly).
    func testThemeGridsAreDisjointAndComplete() {
        let light = Set(ReaderTheme.lightCases)
        let dark = Set(ReaderTheme.darkCases)
        XCTAssertTrue(light.isDisjoint(with: dark))
        XCTAssertEqual(light.union(dark), Set(ReaderTheme.allCases))
        XCTAssertTrue(light.allSatisfy { !$0.isDark })
        XCTAssertTrue(dark.allSatisfy(\.isDark))
    }
}
