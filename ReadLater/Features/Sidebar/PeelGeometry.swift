import CoreGraphics

/// The maths behind the layer-1 peel, kept pure so the thresholds are
/// unit-testable and so the view layer holds no arithmetic (see
/// `PeelGeometryTests`).
///
/// The navigation model (issue #57):
///
/// - **layer 0** the sidebar — the app's root, always mounted underneath.
/// - **layer 1** the group/list view — a full-height card over the sidebar.
/// - **layer 2** the reader — a normal `NavigationStack` push inside the card.
///
/// One gesture peels one layer: inside the card the system's interactive pop
/// handles reader → list; at the card's root our screen-edge pan handles
/// list → sidebar, tracking the finger exactly like a pop does.
///
/// `offset` is the card's translation from its at-rest position: `0` means the
/// card covers the screen, `width` means it has slid fully off to the trailing
/// edge and the sidebar is exposed.
enum PeelGeometry {
    /// Past this fraction of the width (after velocity projection) the card
    /// commits to peeling instead of snapping back.
    static let dismissFraction: CGFloat = 0.35
    /// A flick faster than this decides the outcome on its own, whatever the
    /// distance — the standard "throw it and it goes" feel of a pop.
    static let escapeVelocity: CGFloat = 700
    /// Seconds of velocity projected past the lift, matching UIKit's own
    /// projection for interactive transitions.
    static let projection: CGFloat = 0.2
    /// How far the sidebar sits behind the card at rest, as a fraction of the
    /// width. It catches up to 0 as the card peels — the parallax that makes
    /// layer 0 read as *beneath* rather than *beside*.
    static let parallaxDepth: CGFloat = 0.22
    /// Scrim over the covered sidebar, at full cover.
    static let maxDim: Double = 0.28

    /// Card translation for a live drag, clamped to the travel range.
    static func offset(base: CGFloat, translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(base + translation, 0), width)
    }

    /// 0 = the card covers the sidebar, 1 = the sidebar is fully revealed.
    static func progress(offset: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(offset / width, 0), 1)
    }

    /// Where the card lands when the finger lifts. `true` = peel to the
    /// sidebar, `false` = snap back over it.
    ///
    /// Symmetric on purpose: the same call decides a leading-edge peel (base
    /// 0, positive translation) and a trailing-edge restore (base `width`,
    /// negative translation), so a cancelled drag in either direction returns
    /// to where it started.
    static func shouldPeel(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        if velocity > escapeVelocity { return true }
        if velocity < -escapeVelocity { return false }
        return offset + velocity * projection > width * dismissFraction
    }

    /// Leading offset of the sidebar beneath the card.
    static func sidebarParallax(progress: CGFloat, width: CGFloat) -> CGFloat {
        -width * parallaxDepth * (1 - progress)
    }

    /// Scrim opacity over the sidebar. Fades out as the card gets out of the way.
    static func dim(progress: CGFloat) -> Double {
        maxDim * Double(1 - progress)
    }

    /// The card's corner radius. Square while it covers the screen (a rounded
    /// corner there would just leak the sidebar into the display corners), and
    /// it reaches the §7.2 floating-panel radius as soon as the peel starts.
    static func cornerRadius(progress: CGFloat) -> CGFloat {
        Radius.floatingPanel * min(1, progress * 4)
    }

    /// Shadow strength under the card's leading edge — 0 at rest, full once
    /// the peel is visibly under way.
    static func shadowScale(progress: CGFloat) -> Double {
        Double(min(1, progress * 4))
    }
}
