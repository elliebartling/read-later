import CoreGraphics
import XCTest
@testable import ReadLater

/// The layer-1 peel's thresholds and clamps (issue #57's navigation model).
/// The view layer holds no arithmetic, so everything the gesture decides is
/// decided here.
final class PeelGeometryTests: XCTestCase {
    private let width: CGFloat = 393 // iPhone 16 point width

    // MARK: - Travel

    func testOffsetClampsToTravelRange() {
        XCTAssertEqual(PeelGeometry.offset(base: 0, translation: -200, width: width), 0)
        XCTAssertEqual(PeelGeometry.offset(base: 0, translation: 1_000, width: width), width)
        XCTAssertEqual(PeelGeometry.offset(base: 0, translation: 120, width: width), 120)
    }

    /// The trailing-edge restore drags the same value the other way.
    func testOffsetFromPeeledBase() {
        XCTAssertEqual(PeelGeometry.offset(base: width, translation: -100, width: width),
                       width - 100)
        XCTAssertEqual(PeelGeometry.offset(base: width, translation: -1_000, width: width), 0)
    }

    func testZeroWidthIsInert() {
        XCTAssertEqual(PeelGeometry.offset(base: 0, translation: 50, width: 0), 0)
        XCTAssertEqual(PeelGeometry.progress(offset: 50, width: 0), 0)
        XCTAssertFalse(PeelGeometry.shouldPeel(offset: 50, velocity: 5_000, width: 0))
    }

    func testProgressIsNormalisedAndClamped() {
        XCTAssertEqual(PeelGeometry.progress(offset: 0, width: width), 0)
        XCTAssertEqual(PeelGeometry.progress(offset: width, width: width), 1)
        XCTAssertEqual(PeelGeometry.progress(offset: width / 2, width: width), 0.5, accuracy: 0.001)
        XCTAssertEqual(PeelGeometry.progress(offset: -80, width: width), 0)
        XCTAssertEqual(PeelGeometry.progress(offset: width * 2, width: width), 1)
    }

    // MARK: - Commit / cancel

    func testShortSlowDragSnapsBack() {
        XCTAssertFalse(PeelGeometry.shouldPeel(offset: 40, velocity: 0, width: width))
    }

    func testDragPastThresholdCommits() {
        let past = width * PeelGeometry.dismissFraction + 1
        XCTAssertTrue(PeelGeometry.shouldPeel(offset: past, velocity: 0, width: width))
    }

    /// A flick decides on its own, however short — the "throw it and it goes"
    /// half of a pop.
    func testFlickCommitsFromAlmostNoTravel() {
        XCTAssertTrue(PeelGeometry.shouldPeel(offset: 12, velocity: 1_400, width: width))
    }

    /// …and a flick back cancels even from most of the way across.
    func testReverseFlickCancelsFromDeepTravel() {
        XCTAssertFalse(PeelGeometry.shouldPeel(offset: width * 0.8, velocity: -1_400, width: width))
    }

    /// Velocity is projected, not just thresholded: a moderate push near the
    /// threshold carries over it.
    func testVelocityProjectionCarriesAModerateDrag() {
        let justUnder = width * PeelGeometry.dismissFraction - 20
        XCTAssertFalse(PeelGeometry.shouldPeel(offset: justUnder, velocity: 0, width: width))
        XCTAssertTrue(PeelGeometry.shouldPeel(offset: justUnder, velocity: 400, width: width))
    }

    // MARK: - The look of the layers beneath

    func testSidebarParallaxCatchesUpAsTheCardLeaves() {
        XCTAssertEqual(PeelGeometry.sidebarParallax(progress: 0, width: width),
                       -width * PeelGeometry.parallaxDepth, accuracy: 0.001)
        XCTAssertEqual(PeelGeometry.sidebarParallax(progress: 1, width: width), 0, accuracy: 0.001)
    }

    func testDimFadesOutWithTheCard() {
        XCTAssertEqual(PeelGeometry.dim(progress: 0), PeelGeometry.maxDim, accuracy: 0.001)
        XCTAssertEqual(PeelGeometry.dim(progress: 1), 0, accuracy: 0.001)
    }

    /// Square while it covers the screen, §7.2's floating-panel radius as soon
    /// as the peel is visibly under way.
    func testCornerRadiusRampsFromSquare() {
        XCTAssertEqual(PeelGeometry.cornerRadius(progress: 0), 0)
        XCTAssertEqual(PeelGeometry.cornerRadius(progress: 0.25), Radius.floatingPanel,
                       accuracy: 0.001)
        XCTAssertEqual(PeelGeometry.cornerRadius(progress: 1), Radius.floatingPanel,
                       accuracy: 0.001)
    }

    func testShadowIsAbsentAtRest() {
        XCTAssertEqual(PeelGeometry.shadowScale(progress: 0), 0, accuracy: 0.001)
        XCTAssertEqual(PeelGeometry.shadowScale(progress: 0.5), 1, accuracy: 0.001)
    }
}
