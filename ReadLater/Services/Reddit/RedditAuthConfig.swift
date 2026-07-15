import Foundation

/// Single configuration point for "Sign in with Reddit" (wave 2). Everything the
/// OAuth flow needs that is deployment-specific lives here so there is exactly
/// one thing to fill in when the app is registered.
///
/// ## Registering the app (the one blocked step)
/// Ellen has not yet created the Reddit app. When she does:
/// 1. Go to <https://www.reddit.com/prefs/apps> → "create app".
/// 2. Type: **installed app** (public client, no secret — this is why the flow
///    below uses PKCE and never sends a client secret).
/// 3. Redirect URI: exactly `readlater://oauth/reddit` (already registered as a
///    `CFBundleURLScheme` — see project.yml).
/// 4. Copy the client ID (the string under the app name) into ``clientID``.
///
/// Until ``clientID`` is non-empty the entire feature hides itself
/// (``isConfigured`` is false), so shipping with an empty string is safe — no
/// dead "Sign in" button that can only fail.
enum RedditAuthConfig {

    /// Reddit "installed app" client ID. **Empty by default** — fill this in
    /// after registering the app (see the type doc). Empty string ⇒ the whole
    /// Sign-in-with-Reddit surface is hidden.
    ///
    /// This is a public client identifier, not a secret: installed-app OAuth has
    /// no client secret, and the ID is visible in the authorization URL anyway.
    /// Keeping it here (not in Keychain) is correct and intentional.
    static let clientID = ""

    /// Redirect URI registered with the Reddit app. Must match byte-for-byte
    /// both here and in the Reddit app settings. The `readlater` scheme is
    /// already declared in project.yml, and ASWebAuthenticationSession
    /// intercepts this callback by scheme (see ``callbackURLScheme``) — it never
    /// reaches `RootView.onOpenURL`, so this URL is deliberately distinct from
    /// the app's `save`/`open` deep-link hosts.
    static let redirectURI = "readlater://oauth/reddit"

    /// Scheme ASWebAuthenticationSession watches for to capture the redirect.
    static let callbackURLScheme = "readlater"

    /// OAuth scopes requested. Rationale, per feature:
    /// - `identity`     — read the signed-in account (surface "connected as …").
    /// - `mysubreddits` — list subscriptions for the subreddit import picker.
    /// - `history`      — read the user's saved posts for the saved-posts import.
    /// - `save`         — save a post back to Reddit from the reader.
    /// - `read`         — read listing/link data backing the imports.
    static let scopes = ["identity", "mysubreddits", "history", "save", "read"]

    /// Descriptive User-Agent sent on every oauth.reddit.com call. Reddit's API
    /// rules require a unique, app-identifying UA (generic/blank UAs are
    /// throttled hard). Mirrors ``RedditPolicy.userAgent`` used for anonymous
    /// RSS, but version-stamped for the OAuth surface.
    static let userAgent = "ios:com.ellenbartling.readlater:v0.1.0 (personal read-later app)"

    /// True once a client ID has been supplied. The Settings surface and the
    /// reader save-back gate on this so an unconfigured build shows nothing.
    static var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Endpoints

    /// Authorization endpoint (the page shown in the auth web view). Note this is
    /// `www.reddit.com`, not `oauth.reddit.com` — only the token/API calls use
    /// the oauth host.
    static let authorizeURL = URL(string: "https://www.reddit.com/api/v1/authorize")!

    /// Token exchange + refresh + revoke endpoints (Basic-auth with the client ID
    /// as username and an empty password, per installed-app OAuth).
    static let tokenURL = URL(string: "https://www.reddit.com/api/v1/access_token")!
    static let revokeURL = URL(string: "https://www.reddit.com/api/v1/revoke_token")!

    /// Base for authenticated API calls once a token is held.
    static let apiBaseURL = URL(string: "https://oauth.reddit.com")!
}
