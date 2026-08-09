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
