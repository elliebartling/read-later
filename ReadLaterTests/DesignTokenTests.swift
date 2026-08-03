import XCTest
import UIKit
@testable import ReadLater

/// Guards the wave-1 ground: the palette values, the contrast figures the
/// design language claims for them, the three control tiers, and the shared
/// chrome-inset math both readers depend on.
///
/// These are cheap to run and they catch the class of regression that is
/// otherwise invisible until someone screenshots the app in the other scheme.
final class DesignTokenTests: XCTestCase {

    private let dark = UITraitCollection(userInterfaceStyle: .dark)
    private let light = UITraitCollection(userInterfaceStyle: .light)

    // MARK: - §2.1 / §2.2 values

    func testNeutralRampMatchesTheDesignLanguage() {
        assertHex(Surface.groundUI, dark: 0x21_1F1C, light: 0xF8_F6F5)
        assertHex(Surface.raisedUI, dark: 0x2C_2A27, light: 0xFF_FEFD)
        assertHex(Surface.elevatedUI, dark: 0x37_3532, light: 0xFF_FFFF)
        assertHex(Surface.controlUI, dark: 0x44_423F, light: 0xED_EAE8)
        assertHex(Surface.dividerUI, dark: 0x33_312F, light: 0xE1_DFDD)

        assertHex(Ink.primaryUI, dark: 0xF2_F0ED, light: 0x23_201C)
        assertHex(Ink.secondaryUI, dark: 0xB3_B0AD, light: 0x5E_5A55)
        assertHex(Ink.tertiaryUI, dark: 0x9C_9996, light: 0x71_6C67)
        assertHex(Ink.quaternaryUI, dark: 0x6B_6866, light: 0x9B_9893)
    }

    func testSemanticAndSourceFamiliesMatchTheDesignLanguage() {
        assertHex(Semantic.successUI, dark: 0x51_C672, light: 0x00_7E17)
        assertHex(Semantic.destructiveUI, dark: 0xFF_716B, light: 0xC2_0011)
        assertHex(Semantic.warningUI, dark: 0xE4_9900, light: 0x9E_4900)

        assertHex(Source.youtubeUI, dark: 0xE8_605B, light: 0xCF_4040)
        assertHex(Source.redditUI, dark: 0xDC_7200, light: 0xC4_5500)
        assertHex(Source.websiteUI, dark: 0x3F_93F7, light: 0x17_79E1)
    }

    /// N5: no pure black and no pure white as a page ground.
    func testGroundIsNeverPureBlackOrPureWhite() {
        for traits in [dark, light] {
            let ground = Surface.groundUI.resolvedColor(with: traits)
            XCTAssertNotEqual(hex(of: ground), 0x00_0000)
            XCTAssertNotEqual(hex(of: ground), 0xFF_FFFF)
        }
    }

    // MARK: - §2.3 the accent binding

    /// A2: `Accent.onFill` flips with the binding, so it is a token in both
    /// schemes rather than a hardcoded white or black.
    func testAccentOnFillIsSchemeReactive() {
        let onFillDark = hex(of: Accent.onFillUI.resolvedColor(with: dark))
        let onFillLight = hex(of: Accent.onFillUI.resolvedColor(with: light))
        XCTAssertNotEqual(onFillDark, onFillLight)
        XCTAssertNotEqual(onFillDark, 0xFF_FFFF)
        XCTAssertNotEqual(onFillLight, 0xFF_FFFF)
    }

    /// `Accent.onFill` has to stay legible on `Accent.fill` whatever the
    /// binding is — this is the check that makes a later rebind safe.
    func testAccentOnFillIsLegibleOnAccentFill() {
        for traits in [dark, light] {
            let ratio = contrast(
                Accent.onFillUI.resolvedColor(with: traits),
                Accent.fillUI.resolvedColor(with: traits)
            )
            XCTAssertGreaterThan(ratio, 4.5, "Accent.onFill on Accent.fill: \(ratio):1")
        }
    }

    // MARK: - Contrast claims from §2.1

    func testInkIsBodySafeOnGround() {
        for traits in [dark, light] {
            let ground = Surface.groundUI.resolvedColor(with: traits)
            for (name, token) in [
                ("Ink.primary", Ink.primaryUI),
                ("Ink.secondary", Ink.secondaryUI),
                ("Ink.tertiary", Ink.tertiaryUI),
            ] {
                let ratio = contrast(token.resolvedColor(with: traits), ground)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(name) on Surface.ground is \(String(format: "%.1f", ratio)):1"
                )
            }
        }
    }

    /// §2.1 promises `Ink.secondary` is body-safe on *every* surface, not just
    /// the ground — it carries every row summary and metadata line.
    func testInkSecondaryIsBodySafeOnEverySurface() {
        for traits in [dark, light] {
            for (name, surface) in [
                ("ground", Surface.groundUI),
                ("raised", Surface.raisedUI),
                ("elevated", Surface.elevatedUI),
            ] {
                let ratio = contrast(
                    Ink.secondaryUI.resolvedColor(with: traits),
                    surface.resolvedColor(with: traits)
                )
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "Ink.secondary on Surface.\(name) is \(String(format: "%.1f", ratio)):1"
                )
            }
        }
    }

    /// Markers carry `Ink.primary`'s dark value, never white — white on the
    /// yellow marker is 1.5:1.
    func testMarkerGlyphColourIsLegibleOnEveryMarker() {
        for (name, marker) in [
            ("yellow", HighlightMarker.yellowUI),
            ("green", HighlightMarker.greenUI),
            ("blue", HighlightMarker.blueUI),
            ("pink", HighlightMarker.pinkUI),
        ] {
            let ours = contrast(HighlightMarker.onMarkerUI, marker)
            XCTAssertGreaterThan(ours, 4.5, "onMarker on \(name) is \(ours):1")
            XCTAssertGreaterThan(
                ours, contrast(.white, marker),
                "white would beat our glyph colour on \(name) — check the token"
            )
        }
    }

    // MARK: - §7.1 control tiers

    func testThereAreExactlyThreeControlTiers() {
        XCTAssertEqual(ControlTier.small.height, 28)
        XCTAssertEqual(ControlTier.standard.height, 44)
        XCTAssertEqual(ControlTier.prominent.height, 52)
        XCTAssertEqual(ControlTier.small.glyph, 14)
        XCTAssertEqual(ControlTier.standard.glyph, 17)
        XCTAssertEqual(ControlTier.prominent.glyph, 20)
        // Z1 — the hit-target floor is the Standard height.
        XCTAssertEqual(ControlTier.hitTarget, ControlTier.standard.height)
    }

    /// Z3 — an inner radius is the outer radius minus the padding between them.
    ///
    /// NOTE: §7.2's worked example ("a 16pt container with 16pt padding holds
    /// 8pt-radius children") does not follow from its own formula, which gives
    /// 0. The formula is the rule and the example is illustrative, so the
    /// formula wins here; flagged for Ellen.
    func testNestedRadiusRule() {
        XCTAssertEqual(Radius.nested(in: 16, padding: 8), 8)
        XCTAssertEqual(Radius.nested(in: Radius.container, padding: Metric.containerPadding), 0)
        XCTAssertEqual(Radius.nested(in: 16, padding: 24), 0, "never negative")
    }

    // MARK: - §3 S5/S6 chrome insets

    /// §7.3 — the action bar is 44pt, floats 16pt above the safe area, and
    /// publishes height + 12pt of clearance as a content inset (S5).
    func testReaderBottomReserveCoversTheActionBar() {
        XCTAssertEqual(ReaderChrome.actionBarHeight, 44)
        XCTAssertEqual(ReaderChrome.bottomReserve, 16 + 44 + 12)
        XCTAssertGreaterThan(
            ReaderChrome.bottomReserve,
            ReaderChrome.actionBarBottomOffset + ReaderChrome.actionBarHeight,
            "content must clear the capsule, not merely touch it"
        )
    }

    /// S6 — the top inset freezes at the immersive value, so revealing chrome
    /// never moves the article. Both readers call this.
    func testFrozenTopNeverGrowsWhenChromeIsRevealed() {
        let immersive = ReaderChrome.frozenTop(live: 59, frozen: nil)
        XCTAssertEqual(immersive, 59)
        // Chrome revealed: the safe area grows to include the nav bar.
        XCTAssertEqual(ReaderChrome.frozenTop(live: 148, frozen: immersive), 59)
        // …and back again, still frozen.
        XCTAssertEqual(ReaderChrome.frozenTop(live: 59, frozen: 59), 59)
    }

    /// A transient zero (mid-transition, detached view) must not unfreeze or
    /// shrink the inset — that regression flushed the article to the notch.
    func testFrozenTopIgnoresTransientZero() {
        XCTAssertEqual(ReaderChrome.frozenTop(live: 0, frozen: 59), 59)
        XCTAssertNil(ReaderChrome.frozenTop(live: 0, frozen: nil))
    }

    /// A smaller-but-positive value (rotation, a different device metric) does
    /// take over — the freeze is a minimum, not a first-write-wins.
    func testFrozenTopTakesTheSmallestPositiveValue() {
        XCTAssertEqual(ReaderChrome.frozenTop(live: 24, frozen: 59), 24)
    }

    // MARK: - Helpers

    private func assertHex(
        _ color: UIColor,
        dark expectedDark: UInt32,
        light expectedLight: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            hex(of: color.resolvedColor(with: dark)), expectedDark,
            "dark value", file: file, line: line
        )
        XCTAssertEqual(
            hex(of: color.resolvedColor(with: light)), expectedLight,
            "light value", file: file, line: line
        )
    }

    private func hex(of color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG 2.1 relative-luminance contrast ratio.
    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
