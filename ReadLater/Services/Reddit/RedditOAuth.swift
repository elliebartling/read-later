import CryptoKit
import Foundation

/// Pure, network-free OAuth helpers for the Reddit installed-app flow
/// (authorization code + PKCE). Everything here is a value transform — PKCE
/// generation, authorization-URL assembly, request-body encoding, token-response
/// parsing — so it is unit-testable without a network, a client ID, or a live
/// browser. The side-effecting legs (presenting the auth web view, POSTing to
/// the token endpoint) live in ``RedditAuthController`` / ``RedditAPIClient``.
///
/// ## Why ASWebAuthenticationSession (and not our cookie-based site logins)
/// The app already has a cookie-jar "site login" mechanism (`SiteLoginStore` +
/// an in-app `WKWebView`) for reading member-only articles. OAuth deliberately
/// does **not** reuse it: OAuth's security model requires the authorization
/// request to run in a browser context the app cannot script or read, so the
/// app never sees the user's Reddit password or session cookies — it only
/// receives the redirect's authorization `code`. `ASWebAuthenticationSession` is
/// Apple's sanctioned primitive for exactly that (isolated browser, scheme-based
/// redirect capture). The cookie mechanism, by contrast, is a shared jar the
/// parser reads — appropriate for "log into a paywall", categorically wrong for
/// "authorize a third-party token". They stay separate on purpose.
enum RedditOAuth {

    // MARK: - PKCE

    /// A PKCE code_verifier/code_challenge pair (RFC 7636, S256).
    struct PKCE: Equatable {
        /// High-entropy random string sent (secretly) only on the token
        /// exchange. 43–128 chars of the unreserved set.
        let codeVerifier: String
        /// `base64url(SHA256(codeVerifier))`, no padding — sent in the
        /// authorization URL.
        let codeChallenge: String
        /// Always "S256"; Reddit supports it and it's the only method we use.
        let method = "S256"
    }

    /// Generates a fresh PKCE pair. The verifier is 64 random bytes
    /// base64url-encoded (~86 chars, comfortably within 43–128).
    static func makePKCE() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URLEncode(Data(bytes))
        return PKCE(codeVerifier: verifier, codeChallenge: challenge(for: verifier))
    }

    /// Derives the S256 code_challenge for a given verifier. Pure and
    /// deterministic — the seam the unit tests pin (fixed verifier ⇒ known
    /// challenge).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Base64url without padding (RFC 4648 §5): `+`→`-`, `/`→`_`, drop `=`.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Random URL-safe `state` value for CSRF protection, echoed back on the
    /// redirect and compared for equality.
    static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    // MARK: - Authorization URL

    /// Builds the authorization URL the auth web view loads. `duration=permanent`
    /// is what makes Reddit issue a **refresh token** (temporary yields only a
    /// 1-hour access token with no refresh).
    static func authorizationURL(
        clientID: String,
        redirectURI: String,
        scopes: [String],
        state: String,
        codeChallenge: String
    ) -> URL? {
        var comps = URLComponents(url: RedditAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "duration", value: "permanent"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            // PKCE:
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return comps?.url
    }

    /// Extracts the authorization `code` from the redirect URL, validating the
    /// echoed `state`. Throws on a mismatch or a Reddit-reported error (e.g. the
    /// user tapped Decline ⇒ `error=access_denied`).
    static func authorizationCode(
        fromRedirect url: URL,
        expectedState: String
    ) throws -> String {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw RedditAuthError.authorizationFailed(error)
        }
        guard let state = items.first(where: { $0.name == "state" })?.value,
              state == expectedState
        else { throw RedditAuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw RedditAuthError.missingCode
        }
        return code
    }

    // MARK: - Token request bodies

    /// x-www-form-urlencoded body for exchanging an authorization code for
    /// tokens. Installed-app PKCE ⇒ include `code_verifier`, no client secret.
    static func tokenExchangeBody(code: String, redirectURI: String, codeVerifier: String) -> String {
        formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
        ])
    }

    /// Body for refreshing an expired access token with a stored refresh token.
    static func refreshBody(refreshToken: String) -> String {
        formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    /// Body for revoking a token on sign-out (`token_type_hint` improves
    /// Reddit's bookkeeping but is optional).
    static func revokeBody(token: String, isRefreshToken: Bool) -> String {
        formEncode([
            "token": token,
            "token_type_hint": isRefreshToken ? "refresh_token" : "access_token",
        ])
    }

    /// HTTP Basic credential for the token endpoints: installed-app clients
    /// authenticate as `client_id:` (empty password). Returns the
    /// `Authorization` header value (`Basic <base64>`).
    static func basicAuthHeader(clientID: String) -> String {
        let raw = "\(clientID):"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Token response parsing

    /// Reddit's token endpoint response. `refresh_token` is absent on a refresh
    /// (the existing one stays valid), so it's optional.
    struct TokenResponse: Decodable, Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let scope: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
        }
    }

    /// Parses a token-endpoint JSON payload, mapping Reddit's `{"error": …}`
    /// shape to a thrown ``RedditAuthError`` instead of a decode failure.
    static func parseTokenResponse(_ data: Data) throws -> TokenResponse {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = obj["error"] as? String
        {
            throw RedditAuthError.tokenExchangeFailed(error)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw RedditAuthError.tokenExchangeFailed("Malformed token response")
        }
    }

    // MARK: - Private

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .sorted() // deterministic ordering so bodies are testable
            .joined(separator: "&")
    }
}

/// Errors surfaced by the Reddit OAuth flow.
enum RedditAuthError: LocalizedError, Equatable {
    case notConfigured
    case authorizationFailed(String)
    case stateMismatch
    case missingCode
    case tokenExchangeFailed(String)
    case notSignedIn
    case userCancelled
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sign in with Reddit isn't configured in this build."
        case .authorizationFailed(let reason):
            return reason == "access_denied"
                ? "Reddit sign-in was declined."
                : "Reddit authorization failed (\(reason))."
        case .stateMismatch:
            return "Reddit sign-in couldn't be verified. Please try again."
        case .missingCode:
            return "Reddit didn't return an authorization code."
        case .tokenExchangeFailed(let reason):
            return "Couldn't complete Reddit sign-in (\(reason))."
        case .notSignedIn:
            return "You're not signed in to Reddit."
        case .userCancelled:
            return "Reddit sign-in was cancelled."
        case .network(let reason):
            return reason
        }
    }
}
