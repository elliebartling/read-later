import SwiftUI

// **BR3 / I9** — the three source-kind silhouettes.
//
// Source-*kind* identity (the YouTube / Reddit / Websites groups) is a
// monochrome platform silhouette in `Accent.onFill` on a chip filled with the
// normalised `Source.*` hue. Never the full-colour multi-element logo, never a
// wordmark, never a logo on a white plate.
//
// The audit found all three fidelities in a single column: a real YouTube brand
// mark, generic orange speech bubbles for Reddit, and a system blue globe for
// websites. Nothing about that reads as one family, because nothing about it
// *was* one family — three different artists, three stroke weights, three
// optical sizes.
//
// These are drawn here, by us, to §5.3's permanent custom-glyph slot 3
// ("three platform silhouettes redrawn to one stroke weight and one optical
// size, so YouTube, Reddit and a website sit in a column as siblings") and to
// **I9**: 2pt stroke on a 24pt grid, round caps, no fills, no gradients, no
// two-tone. They are ours, so **I11** — "until the comp is run, no third-party
// icon ships" — is satisfied: nothing here comes from Tabler or Phosphor, and
// §5.3 says these survive that migration unchanged anyway.
//
// **BR7.** They exist solely to identify the source of user-saved content. No
// mark is recoloured *within* its own silhouette, none appears in our branding,
// and none takes a prominent slot (BR4).

/// The line-art silhouette for one source kind, drawn on I9's 24pt grid.
///
/// The path is authored in a 24×24 space and scaled to the requested rect, so
/// the stroke scales with it — the same relationship SF Symbols keep between
/// weight and optical size (I2). One `StrokeStyle` for all three is the whole
/// point: it is what makes them siblings.
struct SourceKindShape: Shape {
    let kind: FeedSourceKind

    /// I9's grid.
    static let grid: CGFloat = 24
    /// I9's stroke, at the grid size.
    static let strokeWidth: CGFloat = 2

    /// The stroke to use when the mark is drawn at `size`.
    static func stroke(at size: CGFloat) -> StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth * size / grid,
            lineCap: .round,
            lineJoin: .round
        )
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .youtube: appendYouTube(to: &path)
        case .reddit: appendReddit(to: &path)
        case .web: appendWeb(to: &path)
        }
        let scale = min(rect.width, rect.height) / Self.grid
        return path.applying(
            CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        )
    }

    /// A 16:9 screen with a play triangle — the video idea, not the brand mark.
    private func appendYouTube(to path: inout Path) {
        path.addRoundedRect(
            in: CGRect(x: 2.5, y: 5.5, width: 19, height: 13),
            cornerSize: CGSize(width: 4, height: 4),
            style: .continuous
        )
        path.move(to: CGPoint(x: 10.2, y: 8.8))
        path.addLine(to: CGPoint(x: 16, y: 12))
        path.addLine(to: CGPoint(x: 10.2, y: 15.2))
        path.closeSubpath()
    }

    /// A head with an antenna — the platform's own silhouette, reduced to the
    /// two shapes that make it recognisable at 14pt.
    private func appendReddit(to path: inout Path) {
        path.addEllipse(in: CGRect(x: 4, y: 8, width: 16, height: 13))
        // Antenna: stem from the crown, terminating in a node.
        path.move(to: CGPoint(x: 12.6, y: 8.2))
        path.addLine(to: CGPoint(x: 15.4, y: 4.4))
        path.addEllipse(in: CGRect(x: 14.6, y: 2, width: 3, height: 3))
        // Eyes: round-capped stubs, so they carry the same 2pt weight as
        // every other stroke rather than becoming filled dots.
        path.move(to: CGPoint(x: 9.2, y: 13.6))
        path.addLine(to: CGPoint(x: 9.2, y: 14.2))
        path.move(to: CGPoint(x: 14.8, y: 13.6))
        path.addLine(to: CGPoint(x: 14.8, y: 14.2))
    }

    /// A globe — meridian and equator, nothing else.
    private func appendWeb(to path: inout Path) {
        path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
        path.addEllipse(in: CGRect(x: 8, y: 3, width: 8, height: 18))
        path.move(to: CGPoint(x: 3.4, y: 12))
        path.addLine(to: CGPoint(x: 20.6, y: 12))
    }
}

/// **BR3.** The kind chip: the silhouette in `Accent.onFill` on a chip filled
/// with that kind's normalised `Source.*` hue.
///
/// **I7** — a glyph is enclosed in a filled chip only when it *identifies a
/// thing*, and a source kind is a thing. **BR5** — the hue is identity only; it
/// never reaches the label, the selection or `Accent.*`.
struct SourceKindChip: View {
    let kind: FeedSourceKind
    /// §7.1 small tier by default: a 14pt mark on a 28pt chip.
    var tier: ControlTier = .small

    var body: some View {
        // Rounded square, matching `FaviconTile` — a source-kind chip and a
        // subscription's artwork sit in the same column, so they share one
        // geometry (Ellen, build 43: "closer to Reeder and Craft").
        RoundedRectangle(cornerRadius: Radius.faviconTile, style: .continuous)
            .fill(kind.tint)
            .frame(width: tier.height, height: tier.height)
            .overlay {
                SourceKindShape(kind: kind)
                    .stroke(
                        Accent.onFill,
                        style: SourceKindShape.stroke(at: tier.glyph)
                    )
                    .frame(width: tier.glyph, height: tier.glyph)
            }
            .accessibilityHidden(true)
    }
}
