import XCTest
import UIKit
import SwiftData
@testable import ReadLater

/// Guards wave 3 — colour & source identity.
///
/// Every assertion here traces to a rule in `docs/design-language.md`: the
/// marker/paint split (§2.2), the hueless system-state wash (H5), the source
/// identity marks (BR1/BR2) and the Highlights grouping (H3).
final class Wave3ColourTests: XCTestCase {

    private let dark = UITraitCollection(userInterfaceStyle: .dark)
    private let light = UITraitCollection(userInterfaceStyle: .light)

    // MARK: - §2.2 Marker / paint split

    func testMarkerIsTheTokenValueNotThePaint() {
        XCTAssertEqual(hex(HighlightColor.yellow.markerUI), 0xF9_CC21)
        XCTAssertEqual(hex(HighlightColor.green.markerUI), 0x43_D066)
        XCTAssertEqual(hex(HighlightColor.blue.markerUI), 0x00_A5ED)
        XCTAssertEqual(hex(HighlightColor.pink.markerUI), 0xF6_519A)
    }

    /// The whole point of the split: the identity chip and the paint behind
    /// text are different values, and the marker is the more saturated one.
    func testMarkerAndPaintAreDistinct() {
        for color in HighlightColor.allCases {
            let marker = components(color.markerUI)
            for darkPage in [true, false] {
                let paint = components(color.uiColor(darkBackground: darkPage))
                XCTAssertNotEqual(hex(color.markerUI),
                                  hex(color.uiColor(darkBackground: darkPage)),
                                  "\(color) marker must not be its paint")
                XCTAssertGreaterThan(
                    saturation(marker), saturation(paint),
                    "\(color) marker should be more saturated than its paint"
                )
            }
        }
    }

    /// Markers carry ink glyphs, never white — white on `#F9CC21` is 1.5:1.
    func testMarkerGlyphColourIsInkNotWhite() {
        XCTAssertEqual(hex(HighlightMarker.onMarkerUI), 0x23_201C)
    }

    // MARK: - H5 System-state wash

    /// Over `Surface.ground` the derived wash reproduces the §2.2 token to
    /// within 1/255 in both schemes — which is what makes deriving it from the
    /// reader's own paper a faithful generalisation rather than a new colour.
    func testWashOverGroundReproducesTheToken() {
        let darkWash = SystemState.washUI(
            overPaper: Surface.groundUI.resolvedColor(with: dark),
            darkBackground: true
        )
        XCTAssertEqual(hex(darkWash), 0x31_2F2C)

        let lightWash = SystemState.washUI(
            overPaper: Surface.groundUI.resolvedColor(with: light),
            darkBackground: false
        )
        assertChannelsWithin(1, hex(lightWash), 0xE9_E7E5)
    }

    /// "A luminance wash only" — the step is equal on every channel, so no
    /// paper can be pushed toward a hue and no wash can be mistaken for a
    /// yellow highlight.
    func testWashIntroducesNoHue() {
        let papers: [(UIColor, Bool)] = [
            (UIColor(rgb: 0xF4_ECD8), false), // sepia
            (UIColor(rgb: 0x1B_2A32), true), // slate
            (UIColor(rgb: 0xFF_FFFF), false),
            (UIColor(rgb: 0x00_0000), true),
        ]
        for (paper, isDark) in papers {
            let base = components(paper)
            let washed = components(SystemState.washUI(overPaper: paper, darkBackground: isDark))
            let dr = washed.r - base.r
            let dg = washed.g - base.g
            let db = washed.b - base.b
            XCTAssertEqual(dr, dg, accuracy: 0.002)
            XCTAssertEqual(dg, db, accuracy: 0.002)
            // Direction: darker on a light page, lighter on a dark one.
            XCTAssertEqual(dr > 0, isDark)
        }
    }

    func testWashClampsAtTheEnds() {
        let white = SystemState.washUI(overPaper: UIColor(rgb: 0xFF_FFFF), darkBackground: true)
        XCTAssertEqual(hex(white), 0xFF_FFFF)
        let black = SystemState.washUI(overPaper: UIColor(rgb: 0x00_0000), darkBackground: false)
        XCTAssertEqual(hex(black), 0x00_0000)
    }

    /// **A1** — the rail is `Accent.primary`, resolved for the *page's*
    /// darkness rather than the UI scheme, because a light-mode app can be
    /// showing a dark paper.
    func testSpokenRailUsesAccentResolvedForThePage() {
        XCTAssertEqual(hex(SystemState.railUI(darkBackground: true)),
                       hex(Accent.primaryUI.resolvedColor(with: dark)))
        XCTAssertEqual(hex(SystemState.railUI(darkBackground: false)),
                       hex(Accent.primaryUI.resolvedColor(with: light)))
        XCTAssertEqual(SystemState.railWidth, 3)
    }

    // MARK: - §6 Source identity (BR1, BR2)

    func testMonogramTakesTheFirstAlphanumeric() {
        XCTAssertEqual(SourceIdentity.monogram(title: "overreacted", host: nil), "O")
        XCTAssertEqual(SourceIdentity.monogram(title: "  •  Hacker News", host: nil), "H")
        XCTAssertEqual(SourceIdentity.monogram(title: "512 Pixels", host: nil), "5")
    }

    func testMonogramFallsBackToHostThenPlaceholder() {
        XCTAssertEqual(SourceIdentity.monogram(title: nil, host: "www.example.com"), "E")
        XCTAssertEqual(SourceIdentity.monogram(title: "   ", host: "news.ycombinator.com"), "N")
        XCTAssertEqual(SourceIdentity.monogram(title: nil, host: nil), "•")
        XCTAssertEqual(SourceIdentity.monogram(title: "—", host: nil), "•")
    }

    func testStrippingWWW() {
        XCTAssertEqual(SourceIdentity.strippingWWW("www.example.com"), "example.com")
        XCTAssertEqual(SourceIdentity.strippingWWW("example.com"), "example.com")
        XCTAssertEqual(SourceIdentity.strippingWWW("wwwx.example.com"), "wwwx.example.com")
    }

    func testFaviconHostNormalisation() {
        XCTAssertEqual(FaviconStore.normalisedHost("WWW.Example.com."), "example.com")
        XCTAssertEqual(FaviconStore.normalisedHost(" news.ycombinator.com "), "news.ycombinator.com")
        // Not a host — short-circuits the fetch rather than issuing three 404s.
        XCTAssertEqual(FaviconStore.normalisedHost("localhost"), "")
        XCTAssertEqual(FaviconStore.normalisedHost(""), "")
    }

    /// Best fidelity first: square apple-touch icons ahead of the 16px
    /// `favicon.ico` that turns to mush on a 20pt mark.
    func testFaviconCandidateOrder() {
        let urls = FaviconStore.candidateURLs(host: "www.example.com").map(\.absoluteString)
        XCTAssertEqual(urls, [
            "https://example.com/apple-touch-icon.png",
            "https://example.com/apple-touch-icon-precomposed.png",
            "https://example.com/favicon.ico",
        ])
        XCTAssertTrue(FaviconStore.candidateURLs(host: "localhost").isEmpty)
    }

    /// **BR5** — the hue is source identity, and the three kinds keep the
    /// normalised §2.2 values wherever a row renders them.
    func testSourceTintFollowsTheKind() {
        XCTAssertEqual(
            FeedSourceKind.kind(feedURL: nil, siteURL: URL(string: "https://www.youtube.com/watch?v=x")),
            .youtube
        )
        XCTAssertEqual(
            FeedSourceKind.kind(feedURL: nil, siteURL: URL(string: "https://www.reddit.com/r/swift/")),
            .reddit
        )
        XCTAssertEqual(
            FeedSourceKind.kind(feedURL: nil, siteURL: URL(string: "https://overreacted.io/post")),
            .web
        )
    }

    // MARK: - §7.1 / H1 swatch sizing

    func testSwatchIsTwentyPointsWithAFortyFourPointTarget() {
        XCTAssertEqual(HighlightSwatch.diameter, 20)
        XCTAssertEqual(ControlTier.hitTarget, 44)
    }

    // MARK: - Helpers

    private func hex(_ color: UIColor) -> UInt32 {
        let c = components(color)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(c.r) << 16 | byte(c.g) << 8 | byte(c.b)
    }

    private func components(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// Max − min channel: a crude but sufficient "how much colour is in this".
    private func saturation(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
    }

    private func assertChannelsWithin(
        _ tolerance: Int,
        _ actual: UInt32,
        _ expected: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for shift in [16, 8, 0] {
            let a = Int((actual >> UInt32(shift)) & 0xFF)
            let e = Int((expected >> UInt32(shift)) & 0xFF)
            XCTAssertLessThanOrEqual(
                abs(a - e), tolerance,
                String(format: "%06X vs %06X", actual, expected),
                file: file, line: line
            )
        }
    }
}

/// **H3** — grouping is the Highlights destination's whole hierarchy fix, so
/// the ordering rules are pinned here. Uses an in-memory SwiftData container
/// because `Highlight.article` is a real relationship.
final class HighlightGroupingTests: XCTestCase {

    func testGroupsByArticleKeepingNewestFirstOrder() throws {
        let context = try Self.makeContext()
        let a = Article(url: URL(string: "https://a.example/1")!, title: "Alpha")
        let b = Article(url: URL(string: "https://b.example/1")!, title: "Beta")
        context.insert(a)
        context.insert(b)

        // Query order is newest-first; grouping must preserve it.
        let h1 = Highlight(article: a, startOffset: 0, endOffset: 4, quotedText: "one")
        let h2 = Highlight(article: b, startOffset: 0, endOffset: 4, quotedText: "two")
        let h3 = Highlight(article: a, startOffset: 9, endOffset: 12, quotedText: "three")
        for h in [h1, h2, h3] { context.insert(h) }

        let groups = HighlightGrouping.group([h1, h2, h3])
        XCTAssertEqual(groups.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(groups[0].highlights.map(\.quotedText), ["one", "three"])
        XCTAssertEqual(groups[1].highlights.map(\.quotedText), ["two"])
    }

    func testOrphanHighlightsGetTheirOwnGroup() throws {
        let context = try Self.makeContext()
        let a = Article(url: URL(string: "https://a.example/1")!, title: "Alpha")
        context.insert(a)
        let owned = Highlight(article: a, startOffset: 0, endOffset: 3, quotedText: "one")
        context.insert(owned)
        let orphan = Highlight(article: a, startOffset: 4, endOffset: 7, quotedText: "two")
        context.insert(orphan)
        orphan.article = nil

        let groups = HighlightGrouping.group([owned, orphan])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[1].title, HighlightGrouping.orphanTitle)
        XCTAssertNil(groups[1].articleID)
    }

    func testUntitledArticleFallsBackToItsHost() throws {
        let context = try Self.makeContext()
        let a = Article(url: URL(string: "https://www.example.com/1")!, title: "   ")
        context.insert(a)
        let h = Highlight(article: a, startOffset: 0, endOffset: 3, quotedText: "one")
        context.insert(h)

        XCTAssertEqual(HighlightGrouping.group([h]).first?.title, "example.com")
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(HighlightGrouping.group([]).isEmpty)
    }

    private static func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Article.self, Highlight.self, Tag.self, Feed.self, FeedEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }
}
