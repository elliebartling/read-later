import CryptoKit
import XCTest
@testable import ReadLater

/// Reddit wave 2 — OAuth math: PKCE generation, authorization-URL assembly,
/// redirect/code extraction, token request bodies, and token-response parsing.
/// All pure and network-free (the live OAuth legs can't be exercised without a
/// registered client ID, so the pure seams carry the coverage).
final class RedditOAuthTests: XCTestCase {

    // MARK: - PKCE

    func testChallengeIsDeterministicS256() {
        // Fixed verifier ⇒ known base64url(SHA256(verifier)), no padding.
        let verifier = "test_verifier_1234567890_abcdefghijklmnopqrstuvwxyz"
        let expectedDigest = SHA256.hash(data: Data(verifier.utf8))
        let expected = RedditOAuth.base64URLEncode(Data(expectedDigest))
        XCTAssertEqual(RedditOAuth.challenge(for: verifier), expected)
        // base64url alphabet: no '+', '/', or '=' padding.
        let challenge = RedditOAuth.challenge(for: verifier)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    func testMakePKCEProducesValidPair() {
        let pkce = RedditOAuth.makePKCE()
        // RFC 7636: verifier length 43...128.
        XCTAssertGreaterThanOrEqual(pkce.codeVerifier.count, 43)
        XCTAssertLessThanOrEqual(pkce.codeVerifier.count, 128)
        XCTAssertEqual(pkce.method, "S256")
        // Challenge must be the S256 transform of THIS verifier.
        XCTAssertEqual(pkce.codeChallenge, RedditOAuth.challenge(for: pkce.codeVerifier))
        // Two generations differ (randomness).
        XCTAssertNotEqual(RedditOAuth.makePKCE().codeVerifier, RedditOAuth.makePKCE().codeVerifier)
    }

    func testBase64URLEncodingHasNoPadding() {
        // 1 byte would normally base64 to "AA==".
        XCTAssertEqual(RedditOAuth.base64URLEncode(Data([0])), "AA")
    }

    // MARK: - Authorization URL

    func testAuthorizationURLContainsRequiredParams() throws {
        let url = try XCTUnwrap(RedditOAuth.authorizationURL(
            clientID: "CLIENT",
            redirectURI: "readlater://oauth/reddit",
            scopes: ["identity", "read"],
            state: "STATE123",
            codeChallenge: "CHAL"
        ))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(comps.host, "www.reddit.com")
        XCTAssertEqual(items["client_id"], "CLIENT")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["state"], "STATE123")
        XCTAssertEqual(items["redirect_uri"], "readlater://oauth/reddit")
        XCTAssertEqual(items["duration"], "permanent")
        XCTAssertEqual(items["scope"], "identity read")
        XCTAssertEqual(items["code_challenge"], "CHAL")
        XCTAssertEqual(items["code_challenge_method"], "S256")
    }

    // MARK: - Redirect / code extraction

    func testAuthorizationCodeSuccess() throws {
        let url = URL(string: "readlater://oauth/reddit?state=S&code=THECODE")!
        XCTAssertEqual(try RedditOAuth.authorizationCode(fromRedirect: url, expectedState: "S"), "THECODE")
    }

    func testAuthorizationCodeStateMismatchThrows() {
        let url = URL(string: "readlater://oauth/reddit?state=WRONG&code=X")!
        XCTAssertThrowsError(try RedditOAuth.authorizationCode(fromRedirect: url, expectedState: "S")) {
            XCTAssertEqual($0 as? RedditAuthError, .stateMismatch)
        }
    }

    func testAuthorizationCodeAccessDeniedThrows() {
        let url = URL(string: "readlater://oauth/reddit?error=access_denied&state=S")!
        XCTAssertThrowsError(try RedditOAuth.authorizationCode(fromRedirect: url, expectedState: "S")) {
            XCTAssertEqual($0 as? RedditAuthError, .authorizationFailed("access_denied"))
        }
    }

    func testAuthorizationCodeMissingCodeThrows() {
        let url = URL(string: "readlater://oauth/reddit?state=S")!
        XCTAssertThrowsError(try RedditOAuth.authorizationCode(fromRedirect: url, expectedState: "S")) {
            XCTAssertEqual($0 as? RedditAuthError, .missingCode)
        }
    }

    // MARK: - Token request bodies

    func testTokenExchangeBody() {
        let body = RedditOAuth.tokenExchangeBody(
            code: "abc",
            redirectURI: "readlater://oauth/reddit",
            codeVerifier: "verifier123"
        )
        // Deterministic (sorted) encoding, PKCE verifier present, no secret.
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=abc"))
        XCTAssertTrue(body.contains("code_verifier=verifier123"))
        XCTAssertTrue(body.contains("redirect_uri=readlater%3A%2F%2Foauth%2Freddit"))
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testRefreshBody() {
        let body = RedditOAuth.refreshBody(refreshToken: "R123")
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=R123"))
    }

    func testBasicAuthHeaderUsesEmptyPassword() {
        // Installed-app clients authenticate as `client_id:` (empty password).
        let header = RedditOAuth.basicAuthHeader(clientID: "CID")
        let expected = "Basic " + Data("CID:".utf8).base64EncodedString()
        XCTAssertEqual(header, expected)
    }

    // MARK: - Token response parsing

    func testParseTokenResponseSuccess() throws {
        let json = """
        {"access_token":"AT","refresh_token":"RT","expires_in":3600,"scope":"identity read"}
        """
        let parsed = try RedditOAuth.parseTokenResponse(Data(json.utf8))
        XCTAssertEqual(parsed.accessToken, "AT")
        XCTAssertEqual(parsed.refreshToken, "RT")
        XCTAssertEqual(parsed.expiresIn, 3600)
        XCTAssertEqual(parsed.scope, "identity read")
    }

    func testParseTokenResponseOmittedRefreshToken() throws {
        // A refresh response omits refresh_token; parsing must still succeed.
        let json = #"{"access_token":"AT2","expires_in":3600,"scope":"identity"}"#
        let parsed = try RedditOAuth.parseTokenResponse(Data(json.utf8))
        XCTAssertNil(parsed.refreshToken)
        XCTAssertEqual(parsed.accessToken, "AT2")
    }

    func testParseTokenResponseErrorThrows() {
        let json = #"{"error":"invalid_grant"}"#
        XCTAssertThrowsError(try RedditOAuth.parseTokenResponse(Data(json.utf8))) {
            XCTAssertEqual($0 as? RedditAuthError, .tokenExchangeFailed("invalid_grant"))
        }
    }

    // MARK: - Stored-token expiry

    func testStoredTokenExpiryLeeway() {
        let soon = RedditStoredTokens(accessToken: "a", refreshToken: "r",
                                      expiresAt: Date().addingTimeInterval(30), scope: "", username: nil)
        XCTAssertTrue(soon.isExpired(), "within 60s leeway ⇒ treated as expired")
        let fresh = RedditStoredTokens(accessToken: "a", refreshToken: "r",
                                       expiresAt: Date().addingTimeInterval(3600), scope: "", username: nil)
        XCTAssertFalse(fresh.isExpired())
    }
}
