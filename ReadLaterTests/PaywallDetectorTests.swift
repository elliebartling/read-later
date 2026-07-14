import XCTest
@testable import ReadLater

/// Fixture-driven tests for the pure `PaywallDetector`.
///
/// The verdict under test means "we likely captured a truncated preview", not
/// "the source is member-only": schema.org `isAccessibleForFree:false` is
/// permanent publisher metadata (it stays false even when an authenticated
/// fetch returned the complete text — the build-31 false positive), so alone
/// it only flags sub-preview-scale captures. In-DOM gate CTAs render only on
/// gated views, so they flag unconditionally.
final class PaywallDetectorTests: XCTestCase {

    /// Medium's real shape: the Article node lives inside an @graph array.
    private let schemaFalseLD = """
    {
      "@context": "https://schema.org",
      "@graph": [
        { "@type": "Person", "name": "A Writer" },
        { "@type": "Article",
          "headline": "The gated one",
          "isAccessibleForFree": false }
      ]
    }
    """

    private var floor: Int { PaywallRules.substantialWordFloor }

    private func signals(schema: Bool, gate: Bool) -> PaywallDetector.Signals {
        PaywallDetector.Signals(schemaSaysNotFree: schema, domGateMarker: gate)
    }

    // MARK: - Verdict: the corrected truncation-evidence semantics

    func testAuthenticatedFullFetchIsNotPartialDespiteSchemaFalse() {
        // Build-31 regression: signed into Medium, re-extract returns the
        // COMPLETE article. Schema still says isAccessibleForFree:false
        // (permanent metadata) but no gate CTA renders and the capture is
        // long-form — must NOT be flagged partial.
        let verdict = PaywallDetector.verdict(
            signals(schema: true, gate: false),
            extractedWordCount: 1800
        )
        XCTAssertEqual(verdict, .free)
    }

    func testAnonymousPreviewIsPartial() {
        // Anonymous Medium fetch: schema false, gate CTAs rendered in place of
        // the body, preview-scale capture.
        let verdict = PaywallDetector.verdict(
            signals(schema: true, gate: true),
            extractedWordCount: 220
        )
        XCTAssertEqual(verdict, PaywallDetector.Result(isPaywalled: true, reason: .domMarker))
    }

    func testGateMarkerWinsEvenOnLongCapture() {
        // Edge: substantial content AND a gate CTA on the page (e.g. the
        // harvester banked pre-gate content, or an unusually long preview).
        // The gate CTA is direct truncation evidence — partial wins over length.
        let verdict = PaywallDetector.verdict(
            signals(schema: true, gate: true),
            extractedWordCount: floor * 3
        )
        XCTAssertEqual(verdict, PaywallDetector.Result(isPaywalled: true, reason: .domMarker))
    }

    func testSchemaAloneFlagsOnlySubPreviewScaleCaptures() {
        // A localized/reworded gate the DOM list misses: schema false + short
        // capture is still caught by the word-count backstop.
        let verdict = PaywallDetector.verdict(
            signals(schema: true, gate: false),
            extractedWordCount: 150
        )
        XCTAssertEqual(verdict, PaywallDetector.Result(isPaywalled: true, reason: .schemaOrg))
    }

    func testSubstantialWordFloorBoundary() {
        let below = PaywallDetector.verdict(signals(schema: true, gate: false),
                                            extractedWordCount: floor - 1)
        XCTAssertTrue(below.isPaywalled, "one word under the floor is preview scale")

        let atFloor = PaywallDetector.verdict(signals(schema: true, gate: false),
                                              extractedWordCount: floor)
        XCTAssertEqual(atFloor, .free, "at the floor counts as substantial")
    }

    func testGateMarkerAloneFlagsWithoutSchema() {
        // Some walls never emit the schema signal; the CTA is enough.
        let verdict = PaywallDetector.verdict(
            signals(schema: false, gate: true),
            extractedWordCount: 300
        )
        XCTAssertEqual(verdict, PaywallDetector.Result(isPaywalled: true, reason: .domMarker))
    }

    func testNoSignalsIsFreeAtAnyLength() {
        XCTAssertEqual(PaywallDetector.verdict(.none, extractedWordCount: 40), .free)
        XCTAssertEqual(PaywallDetector.verdict(.none, extractedWordCount: 5000), .free)
    }

    func testIndicatesGatedSourceCoversEitherSignal() {
        // The parser's retry short-circuit keys off "gated at all" (either raw
        // signal), independent of the truncation verdict.
        XCTAssertTrue(signals(schema: true, gate: false).indicatesGatedSource)
        XCTAssertTrue(signals(schema: false, gate: true).indicatesGatedSource)
        XCTAssertFalse(signals(schema: false, gate: false).indicatesGatedSource)
    }

    // MARK: - End-to-end detect() fixtures

    func testDetectAnonymousMediumPreviewFixture() {
        let body = """
        Here is the free preview of the article, a few honest paragraphs of prose.
        Read the full story with a free account.
        Create an account to read the full story.
        """
        let result = PaywallDetector.detect(
            jsonLDBlobs: [schemaFalseLD], bodyText: body, extractedWordCount: 240
        )
        XCTAssertEqual(result, PaywallDetector.Result(isPaywalled: true, reason: .domMarker))
    }

    func testDetectAuthenticatedMediumFullFixture() {
        // Signed-in page: same JSON-LD, no gate CTAs, full-length capture.
        let body = """
        The complete article text, all sections present, code samples included.
        Nothing on this page asks the reader to create an account because the
        session is authenticated and the wall never rendered.
        """
        let result = PaywallDetector.detect(
            jsonLDBlobs: [schemaFalseLD], bodyText: body, extractedWordCount: 2200
        )
        XCTAssertEqual(result, .free)
    }

    func testDetectFreeArticleFixture() {
        let ld = """
        { "@context": "https://schema.org", "@graph": [
          { "@type": "Article", "headline": "Open access",
            "isAccessibleForFree": true }
        ] }
        """
        let body = "A complete, freely readable article about building software."
        XCTAssertEqual(
            PaywallDetector.detect(jsonLDBlobs: [ld], bodyText: body, extractedWordCount: 120),
            .free
        )
    }

    // MARK: - schema.org signal parsing

    func testDetectsSchemaOrgBooleanFalseInGraph() {
        XCTAssertTrue(PaywallDetector.jsonLDIndicatesPaywall([schemaFalseLD]))
    }

    func testDetectsSchemaOrgStringFalseForm() {
        // Some publishers emit the URI-string form of the schema.org boolean.
        let ld = """
        { "@type": "NewsArticle", "isAccessibleForFree": "http://schema.org/False" }
        """
        XCTAssertTrue(PaywallDetector.jsonLDIndicatesPaywall([ld]))

        let plain = #"{ "isAccessibleForFree": "False" }"#
        XCTAssertTrue(PaywallDetector.jsonLDIndicatesPaywall([plain]))
    }

    func testDetectsSchemaOrgKeyRegardlessOfCase() {
        let ld = #"{ "isaccessibleforfree": false }"#
        XCTAssertTrue(PaywallDetector.jsonLDIndicatesPaywall([ld]))
    }

    func testSchemaTrueOrAbsentIsNotASignal() {
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall(
            [#"{ "@type": "Article", "isAccessibleForFree": true }"#]))
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall(
            [#"{ "@type": "Article", "headline": "Just an article" }"#]))
    }

    func testMalformedJSONLDIsIgnored() {
        // A broken script must never crash or flip the flag.
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall(["{ not valid json ,,,"]))
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall([""]))
    }

    // MARK: - In-DOM marker signal

    func testDetectsMediumReadTheFullStoryGate() {
        XCTAssertTrue(PaywallDetector.bodyIndicatesPaywall(
            "Read the full story with a free account."))
    }

    func testDetectsGenericSubscribeGate() {
        XCTAssertTrue(PaywallDetector.bodyIndicatesPaywall(
            "Enjoying this? Subscribe to keep reading the rest of this piece."))
        XCTAssertTrue(PaywallDetector.bodyIndicatesPaywall(
            "You've reached your free article limit for this month."))
    }

    func testGatePhraseMatchIsCaseInsensitive() {
        XCTAssertTrue(PaywallDetector.bodyIndicatesPaywall("READ THE FULL STORY"))
    }

    func testOrdinaryProseIsNotAMarker() {
        XCTAssertFalse(PaywallDetector.bodyIndicatesPaywall("""
        This is a complete, freely readable article. It talks about writing, about
        building software, and about the joy of finishing a full story from start to
        end without anyone asking you to subscribe to anything at all.
        """))
    }

    func testEmptyBodyIsNotAMarker() {
        XCTAssertFalse(PaywallDetector.bodyIndicatesPaywall(""))
    }
}
