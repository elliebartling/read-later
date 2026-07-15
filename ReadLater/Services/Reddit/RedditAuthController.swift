import AuthenticationServices
import Foundation
import UIKit

/// Owns the "Sign in with Reddit" session state and drives the OAuth flow.
/// A `@MainActor @Observable` singleton (the app's `SiteLoginStore` / `SyncStatus`
/// pattern) so any view can read `account` / `isSignedIn` reactively and trigger
/// sign-in/out. The heavy lifting is delegated: pure OAuth math to
/// ``RedditOAuth``, token persistence to ``RedditTokenStore``, and API calls to
/// the injected ``RedditAPIClientProtocol`` — this type only sequences them and
/// presents the auth web view.
@MainActor
@Observable
final class RedditAuthController {
    static let shared = RedditAuthController()

    /// The connected account, or nil when signed out. Restored from Keychain on
    /// launch (no network) so signed-in state survives relaunch.
    private(set) var account: RedditAccount?
    /// True while a sign-in is in flight (drives the button spinner).
    private(set) var isAuthenticating = false
    /// Last sign-in error to surface, or nil. Cleared when a new attempt starts.
    var lastError: String?

    /// The API client used by imports and the reader save-back. Injectable for
    /// tests; defaults to the live client backed by the refreshing token provider.
    let client: RedditAPIClientProtocol

    private let presentationProvider = PresentationContextProvider()
    /// Retains the in-flight auth session (ASWebAuthenticationSession must be
    /// held for its lifetime or it deallocates and silently cancels).
    private var authSession: ASWebAuthenticationSession?
    private let session: URLSession

    init(
        client: RedditAPIClientProtocol = RedditAPIClient(tokenProvider: RedditTokenProvider()),
        session: URLSession = .shared
    ) {
        self.client = client
        self.session = session
        // Restore signed-in state from the stored bundle without a network hit.
        if let tokens = RedditTokenStore.load(), let username = tokens.username {
            account = RedditAccount(name: username)
        }
    }

    /// Whether the feature should be shown at all (client ID present) — the
    /// single gate the UI checks before rendering any Reddit surface.
    var isConfigured: Bool { RedditAuthConfig.isConfigured }
    var isSignedIn: Bool { account != nil }

    // MARK: - Sign in

    /// Runs the full authorization-code + PKCE flow: present the auth web view,
    /// capture the redirect, exchange the code for tokens, persist them, and
    /// fetch the account identity. Sets `account` on success; sets `lastError`
    /// on failure.
    func signIn() async {
        guard isConfigured else { lastError = RedditAuthError.notConfigured.localizedDescription; return }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        do {
            let pkce = RedditOAuth.makePKCE()
            let state = RedditOAuth.makeState()
            guard let authURL = RedditOAuth.authorizationURL(
                clientID: RedditAuthConfig.clientID,
                redirectURI: RedditAuthConfig.redirectURI,
                scopes: RedditAuthConfig.scopes,
                state: state,
                codeChallenge: pkce.codeChallenge
            ) else { throw RedditAuthError.network("Couldn't build the sign-in URL.") }

            let callback = try await presentAuthSession(url: authURL)
            let code = try RedditOAuth.authorizationCode(fromRedirect: callback, expectedState: state)
            let tokenResponse = try await exchangeCode(code, codeVerifier: pkce.codeVerifier)

            var stored = RedditStoredTokens(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
                scope: tokenResponse.scope,
                username: nil
            )
            RedditTokenStore.save(stored)

            // Identity fills in the display name (and confirms the token works).
            let fetched = try await client.account()
            stored.username = fetched.name
            RedditTokenStore.save(stored)
            account = fetched
        } catch let error as RedditAuthError {
            if case .userCancelled = error { return } // silent on user cancel
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sign out

    /// Revokes the tokens server-side (best-effort) and purges the Keychain
    /// bundle, then clears local state.
    func signOut() async {
        try? await client.revokeTokens()
        RedditTokenStore.clear()
        account = nil
    }

    // MARK: - Save-back

    /// Saves the post identified by a discussion permalink to the user's Reddit
    /// saved list. No-op (throws) when signed out or the permalink isn't a
    /// comments URL. Used by the reader's overflow action.
    func savePost(discussionURL: URL) async throws {
        guard isSignedIn else { throw RedditAuthError.notSignedIn }
        guard let fullname = RedditParsing.postFullname(fromPermalink: discussionURL) else {
            throw RedditAuthError.network("Couldn't identify the Reddit post to save.")
        }
        try await client.save(fullname: fullname)
    }

    // MARK: - Private

    /// Exchanges an authorization code for tokens at the token endpoint (Basic
    /// auth with the client ID, PKCE `code_verifier`, no secret).
    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> RedditOAuth.TokenResponse {
        var request = URLRequest(url: RedditAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue(RedditOAuth.basicAuthHeader(clientID: RedditAuthConfig.clientID), forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(RedditAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(RedditOAuth.tokenExchangeBody(
            code: code,
            redirectURI: RedditAuthConfig.redirectURI,
            codeVerifier: codeVerifier
        ).utf8)
        let (data, _) = try await session.data(for: request)
        return try RedditOAuth.parseTokenResponse(data)
    }

    /// Wraps `ASWebAuthenticationSession` in async/await. Non-ephemeral so the
    /// user's existing Reddit login is visible in the sheet. Maps a user-cancel
    /// to ``RedditAuthError/userCancelled``.
    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: RedditAuthConfig.callbackURLScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    {
                        continuation.resume(throwing: RedditAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: RedditAuthError.network(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: RedditAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: RedditAuthError.network("Couldn't start the sign-in session."))
            }
        }
    }
}

/// Supplies the anchor window for `ASWebAuthenticationSession`. Must be an
/// `NSObject` (the protocol inherits `NSObjectProtocol`).
private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
