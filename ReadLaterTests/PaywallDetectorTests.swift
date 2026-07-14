import XCTest
@testable import ReadLater

/// Fixture-driven tests for the pure `PaywallDetector`. The paywalled fixtures
/// model the two real-world signals — schema.org `isAccessibleForFree:false`
/// (the confirmed ground truth for the reported Medium article) and in-DOM gate
/// CTAs — while the counter-fixtures prove a fully-readable free article is
/// never mislabeled as a preview.
final class PaywallDetectorTests: XCTestCase {

    // MARK: - schema.org: paywalled fixtures

    func testDetectsSchemaOrgBooleanFalse() {
        // Medium's shape: the Article node lives inside an @graph array.
        let ld = """
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
        let result = PaywallDetector.detect(jsonLDBlobs: [ld], bodyText: "")
        XCTAssertEqual(result, PaywallDetector.Result(isPaywalled: true, reason: .schemaOrg))
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

    // MARK: - schema.org: free counter-fixtures

    func testFreeArticleWithAccessibleForFreeTrueIsNotPaywalled() {
        let ld = """
        { "@context": "https://schema.org", "@graph": [
          { "@type": "Article", "headline": "Open access",
            "isAccessibleForFree": true }
        ] }
        """
        XCTAssertEqual(PaywallDetector.detect(jsonLDBlobs: [ld], bodyText: ""), .free)
    }

    func testFreeArticleWithNoAccessibilityKeyIsNotPaywalled() {
        let ld = #"{ "@type": "Article", "headline": "Just an article" }"#
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall([ld]))
    }

    func testMalformedJSONLDIsIgnored() {
        // A broken script must never crash or flip the flag.
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall(["{ not valid json ,,,"]))
        XCTAssertFalse(PaywallDetector.jsonLDIndicatesPaywall([""]))
    }

    // MARK: - In-DOM markers: paywalled fixtures

    func testDetectsMediumReadTheFullStoryGate() {
        let body = """
        Here is the free preview of the article, a few honest paragraphs of prose.
        Read the full story with a free account.
        Create an account to read the full story.
        """
        let result = PaywallDetector.detect(jsonLDBlobs: [], bodyText: body)
        XCTAssertEqual(result, PaywallDetector.Result(isPaywalled: true, reason: .domMarker))
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

    // MARK: - In-DOM markers: free counter-fixtures

    func testOrdinaryProseIsNotFlagged() {
        let body = """
        This is a complete, freely readable article. It talks about writing, about
        building software, and about the joy of finishing a full story from start to
        end without anyone asking you to subscribe to anything at all.
        """
        XCTAssertEqual(PaywallDetector.detect(jsonLDBlobs: [], bodyText: body), .free)
    }

    func testEmptyBodyIsNotFlagged() {
        XCTAssertFalse(PaywallDetector.bodyIndicatesPaywall(""))
    }

    // MARK: - Precedence

    func testSchemaOrgReasonWinsOverDOMMarker() {
        let ld = #"{ "isAccessibleForFree": false }"#
        let body = "Read the full story"
        XCTAssertEqual(PaywallDetector.detect(jsonLDBlobs: [ld], bodyText: body).reason, .schemaOrg)
    }
}
