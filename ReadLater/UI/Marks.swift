import SwiftUI

// §5.3 — the app's custom line art, and the whole answer to "unbranded".
//
// Ellen's iconography note had two halves: the glyphs look *clinical* (a usage
// problem, fixed in wave 2 by `Glyph.swift`) and the app feels *unbranded* (a
// coverage problem — there was nowhere a drawing of ours appeared). §5.3 names
// exactly three places we go custom, and two of them live here:
//
//  1. **The highlight mark** — the app's single identity mark. It marks the
//     Highlights destination and the highlighting empty state, and it is the
//     lineage for the app icon. Drawn as a *mark*, not a marker-pen
//     skeuomorph (N4).
//  2. **Empty-state marks** — one per state, 64pt, 2pt uniform stroke,
//     `Ink.tertiary` (§8.5 E2). An SF Symbol scaled to 64pt is exactly what
//     "unbranded" looks like.
//
// Rules these obey:
//
//  - **I9.** One spec: 2pt stroke on a 24pt grid, round caps, **no fills, no
//    gradients, no two-tone**. A glyph that cannot be drawn at 2pt/24 is out of
//    scope, which is why each mark carries exactly one visual idea.
//  - **I10.** No mascot, no illustration *style*, nothing beyond these.
//  - **N4.** No book spines, no page curls, nothing paper-y — which is why the
//    Library mark is a link landing in a tray rather than a shelf of books.
//  - **I11.** These are ours; they are not third-party artwork, so they are
//    unaffected by the wave-6 glyph migration, which replaces the *system-verb
//    substrate* only (I12).
//
// The geometry is authored on the 24-unit grid and scaled to whatever size the
// call site asks for; the stroke width is a point value, not a scaled one, so a
// 64pt empty-state mark stays the airy 2pt hairline §5.3 specifies rather than
// thickening to a 5pt slab.

/// One custom line-art mark, on I9's 24-unit grid.
enum Mark: String, CaseIterable {
    /// **The identity mark.** A passage with one band lifted out of it — the
    /// Highlights destination, the highlighting empty state, the app-icon
    /// lineage.
    case highlight
    /// A link dropping into an open tray. Library's "nothing saved yet".
    case save
    /// Concentric waves off a point: a subscription river. Feeds, All Items,
    /// and the subreddit picker's empty list.
    case stream
    /// Ring and handle. Search's two empty states.
    case search
    /// A key. Site logins.
    case key
    /// A check in a ring. Every "that worked" terminal state.
    case done
    /// A warning triangle. **E3** — the only mark that ever takes colour, and
    /// only `Semantic.warning`.
    case warning
}

/// Renders a `Mark` at a given size. Not an `Image`: the artwork is a stroked
/// path so the 2pt hairline is exact at every size (I9) rather than whatever a
/// rasteriser makes of it.
struct MarkView: View {
    let mark: Mark
    /// Rendered size. The empty-state slot is `Font.GlyphSize.emptyStateMark`.
    var size: CGFloat = Font.GlyphSize.emptyStateMark
    /// **I9** — 2pt uniform, in points and never scaled with the art.
    var lineWidth: CGFloat = 2

    var body: some View {
        MarkShape(mark: mark)
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

/// The path half of a mark, on the 24-unit grid.
struct MarkShape: Shape {
    let mark: Mark

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let g = Grid(rect: rect)

        switch mark {
        case .highlight:
            // Two rules of body text with a rounded band lifted out of the
            // middle. A band, not a felt-tip stroke (N4): the idea is the
            // *passage*, not the pen.
            path.move(to: g.p(4, 4.5))
            path.addLine(to: g.p(20, 4.5))
            path.addPath(g.roundedRect(x: 2, y: 9, width: 20, height: 6, radius: 3))
            path.move(to: g.p(4, 19.5))
            path.addLine(to: g.p(14, 19.5))

        case .save:
            // A link arriving in an open tray. No book spines (N4).
            path.move(to: g.p(12, 3.5))
            path.addLine(to: g.p(12, 13.5))
            path.move(to: g.p(7.5, 9.5))
            path.addLine(to: g.p(12, 14))
            path.addLine(to: g.p(16.5, 9.5))
            path.move(to: g.p(3, 14))
            path.addLine(to: g.p(3, 20))
            path.addLine(to: g.p(21, 20))
            path.addLine(to: g.p(21, 14))

        case .stream:
            // Waves off a point — a river of subscriptions.
            path.addPath(g.dot(5.5, 18.5))
            path.addPath(g.arc(center: (5.5, 18.5), radius: 7, from: -90, to: 0))
            path.addPath(g.arc(center: (5.5, 18.5), radius: 13, from: -90, to: 0))

        case .search:
            path.addPath(g.circle(center: (10, 10), radius: 6.5))
            path.move(to: g.p(14.8, 14.8))
            path.addLine(to: g.p(20.5, 20.5))

        case .key:
            path.addPath(g.circle(center: (7.5, 16.5), radius: 4))
            path.move(to: g.p(10.4, 13.6))
            path.addLine(to: g.p(20, 4))
            path.move(to: g.p(16.5, 7.5))
            path.addLine(to: g.p(19, 10))

        case .done:
            path.addPath(g.circle(center: (12, 12), radius: 9))
            path.move(to: g.p(7.5, 12.3))
            path.addLine(to: g.p(10.7, 15.5))
            path.addLine(to: g.p(16.5, 8.8))

        case .warning:
            path.move(to: g.p(12, 3.5))
            path.addLine(to: g.p(21.5, 20.5))
            path.addLine(to: g.p(2.5, 20.5))
            path.closeSubpath()
            path.move(to: g.p(12, 9.5))
            path.addLine(to: g.p(12, 14.5))
            path.addPath(g.dot(12, 17.5))
        }

        return path
    }

    /// The 24-unit authoring grid, mapped onto the render rect.
    private struct Grid {
        let rect: CGRect
        private var unit: CGFloat { min(rect.width, rect.height) / 24 }

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }

        func circle(center: (CGFloat, CGFloat), radius: CGFloat) -> Path {
            Path { p in
                p.addArc(
                    center: self.p(center.0, center.1), radius: radius * unit,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false
                )
            }
        }

        func arc(
            center: (CGFloat, CGFloat), radius: CGFloat,
            from start: CGFloat, to end: CGFloat
        ) -> Path {
            Path { p in
                p.addArc(
                    center: self.p(center.0, center.1), radius: radius * unit,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false
                )
            }
        }

        func roundedRect(
            x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat
        ) -> Path {
            Path(roundedRect: CGRect(
                x: rect.minX + x * unit, y: rect.minY + y * unit,
                width: width * unit, height: height * unit
            ), cornerRadius: radius * unit, style: .continuous)
        }

        /// A round cap standing in for a dot — a real filled circle would break
        /// I9's "no fills".
        func dot(_ x: CGFloat, _ y: CGFloat) -> Path {
            Path { p in
                p.move(to: self.p(x, y))
                p.addLine(to: self.p(x, y + 0.01))
            }
        }
    }
}
