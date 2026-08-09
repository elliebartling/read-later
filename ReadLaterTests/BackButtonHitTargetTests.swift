import SwiftUI
import UIKit
import XCTest
@testable import ReadLater

/// Guards the back caret's **tap target**, which is a different number from
/// the circle you can see.
///
/// The bug this file exists for: `phosphorBackButton()` drew `caret-left` as a
/// bare `Image` in a `topBarLeading` slot, so the button laid out at the
/// artwork's width — 12.7pt, measured off the live accessibility frame on an
/// iPhone 17e — inside a glass circle the toolbar draws 44pt wide. Sweeping a
/// tap across the visible circle popped on 3 of 11 positions. It read as "the
/// back button isn't very responsive"; it was a miss, not a delay.
///
/// A constant alone would not have caught it (`ControlTier.hitTarget` was
/// already 44 and already right), so these tests measure the *laid-out view*.
@MainActor
final class BackButtonHitTargetTests: XCTestCase {

    // MARK: - Z1, the target under the glyph

    /// The bare glyph is the "before": proof the defect is real and that the
    /// modifier is load-bearing rather than decorative.
    func testABareStandardGlyphIsFarSmallerThanTheHitTargetFloor() {
        let bare = measure(Image(.caretLeft).uiGlyph())
        XCTAssertLessThan(
            bare.width, ControlTier.hitTarget,
            """
            A bare Standard-tier glyph now lays out at least 44pt wide on its \
            own. If that is really true, `toolbarGlyphHitTarget()` is dead \
            weight — delete it. More likely `uiGlyph` grew a frame.
            """
        )
    }

    func testToolbarGlyphHitTargetMeetsTheFloorInBothAxes() {
        let padded = measure(Image(.caretLeft).uiGlyph().toolbarGlyphHitTarget())
        XCTAssertGreaterThanOrEqual(padded.width, ControlTier.hitTarget)
        XCTAssertGreaterThanOrEqual(padded.height, ControlTier.hitTarget)
    }

    /// `minWidth`, not `width`: the modifier may only ever grow a target.
    func testToolbarGlyphHitTargetNeverShrinksAWiderControl() {
        let wide = measure(
            Text("Something much wider than the floor")
                .toolbarGlyphHitTarget()
        )
        XCTAssertGreaterThan(wide.width, ControlTier.hitTarget)
    }

    /// Both back carets have to wear it. Layer 1's peel button is drawn by
    /// `SidebarBackButton` rather than by `phosphorBackButton()`, which is
    /// exactly the shape of mistake AGENTS.md warns about for the two readers:
    /// one fix, two call sites, and the one you forget regresses silently.
    func testTheLayerOneBackCaretMeetsTheFloorToo() {
        let peel = measure(
            SidebarBackButton().environment(\.peelToSidebar, {})
        )
        XCTAssertGreaterThanOrEqual(peel.width, ControlTier.hitTarget)
        XCTAssertGreaterThanOrEqual(peel.height, ControlTier.hitTarget)
    }

    /// …and it still renders nothing where peeling isn't available.
    func testTheLayerOneBackCaretStaysAbsentWithoutAPeelAction() {
        let none = measure(SidebarBackButton())
        XCTAssertEqual(none, .zero)
    }

    // MARK: - The recognizer that shares the edge

    /// The leading peel zone is 20pt and the back button's target starts at the
    /// 16pt bar inset, so they overlap by 4pt. The recognizer has to fail for
    /// touches that land on the bar or it delays (and can cancel) the press.
    func testTheEdgeZoneAndTheBackButtonTargetDoOverlap() {
        // Nothing to fix if this stops being true — but then `isChrome` is
        // guarding nothing, so it should be revisited rather than trusted.
        XCTAssertGreaterThan(
            EdgePanCatcher.edgeWidth, Metric.containerPadding,
            "The peel zone no longer reaches the bar's leading inset"
        )
    }

    func testATouchInsideANavigationBarIsNotAPeel() {
        let bar = UINavigationBar()
        let buttonWrapper = UIView()
        let glyph = UIView()
        bar.addSubview(buttonWrapper)
        buttonWrapper.addSubview(glyph)

        XCTAssertTrue(EdgePanCatcher.Coordinator.isChrome(glyph))
        XCTAssertTrue(EdgePanCatcher.Coordinator.isChrome(bar))
    }

    func testATouchOnOrdinaryContentIsStillAPeel() {
        let page = UIView()
        let row = UIView()
        page.addSubview(row)

        XCTAssertFalse(EdgePanCatcher.Coordinator.isChrome(row))
        XCTAssertFalse(EdgePanCatcher.Coordinator.isChrome(nil))
    }

    // MARK: - Helpers

    /// Lays a view out at its ideal size, the way a toolbar slot does.
    private func measure(_ view: some View) -> CGSize {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: .max, height: .max))
    }
}
