# Reddit via RSS — design

Status: **approved — two-wave plan.** Ellen approved the plan below; **wave 1 is
built** on branch `claude/reddit-rss-v1`. Wave 2 is scoped here but not built.
Owner file set (wave 1, built): `Shared/Models/FeedEntry.swift`,
`Shared/Models/Article.swift`, `Shared/Models/AppSettings.swift`,
`Shared/PendingSave.swift`, `ReadLater/Services/Feeds/` (parser + fetcher +
`RedditFeed` shim), `ReadLater/Services/Feeds/FeedRefresher.swift`,
`ReadLater/Features/Feeds/FeedsView.swift`,
`ReadLater/Features/Reader/` (discussion affordance),
`ReadLater/Features/Settings/SettingsView.swift`, `project.yml`. Builds on the
existing Feeds feature.

## Approved plan (two waves)

Sections 1–4 below capture the original research and recommendations; they
stand. Ellen's decisions on the open questions (§6) resolved as follows, and
split the work into two waves:

- **Wave 1 (built):** `FeedEntry.externalURL` + `contentHTML`; the `RedditFeed`
  shim (external-link extraction, self-post `capturedHTML` routing);
  `r/name` shorthand (**`r/…` only** for the first cut); **self posts render the
  feed `<content>` HTML** in-app (no extra fetch); the **discussion link ships
  now** as `Article.discussionURL` with a reader affordance + an "Open
  discussions in" setting (System Default / Narwhal / In-app browser); and
  **429 handled by serializing + spacing reddit.com refreshes** with a
  descriptive User-Agent (no `user=`/`feed=` escape hatch yet). See
  "Wave 1 as built" at the bottom for the shipped specifics.
- **Wave 2 (planned):** "Sign in with Reddit" OAuth. See "Wave 2" at the bottom.

## Problem

Reddit publishes Atom feeds for nearly every view, so subscribing "just works"
as a listing through our generic `FeedParser`. But a Reddit entry is not an
article — its `<link>` points at the *comment thread*, and for link posts the
actual article URL is buried inside the entry's HTML content. Tapping an entry
today would push the comments permalink through `ArticleParser`, and Reddit's
comment pages are client-rendered SPAs that Readability extracts to near-nothing.
So the feature is 80% free and 20% Reddit-specific glue — this doc scopes that
20%.

## 1. Reddit's RSS surface today (verified mid-2026)

All of Reddit's listing views append `.rss` and return **Atom 1.0**
(auth-less, no API key). Position matters: `r/rss/top.rss?t=week` works,
`r/rss/top?t=week.rss` does not.

| View | URL |
|------|-----|
| Subreddit hot / new / top / rising | `reddit.com/r/{sub}/.rss`, `/new.rss`, `/top.rss?t={range}`, `/rising.rss` |
| Multireddit (combined subs) | `reddit.com/r/{a}+{b}+{c}/.rss` |
| User page | `reddit.com/user/{name}/.rss` |
| Subreddit comment stream | `reddit.com/r/{sub}/comments.rss` |
| Search | `reddit.com/search.rss?q={q}&sort=new`; sub-scoped `+&restrict_sr=1` |
| Front page | `reddit.com/.rss` |

`t=` accepts `hour|day|week|month|year|all`.

**Rate limits — the real constraint.** In June 2025 Reddit silently cut RSS from
~100 req / 10 min to **~1 req / min** (`x-ratelimit-remaining: 0`,
`x-ratelimit-reset: ~58`), returning **HTTP 429** past that. OAuth gives no
relief. The community workaround is per-*account* `user=` + `feed=` query
params copied from a logged-in user's Reddit RSS-prefs page (same params for
every feed; unofficial, unannounced). Reddit has also announced deprecation of
unauthenticated `.json` endpoints, so **`.rss` is the durable surface — do not
build on `.json`.**

**User-Agent.** Reddit throttles per IP and is hostile to blank / generic-bot
UAs. Our `FeedFetcher.get()` currently sends **no** explicit UA (URLSession's
default `ReadLater/… CFNetwork Darwin`) — descriptive enough to not look like a
scraper, which is what Reddit wants; no need to fake Safari here (that's only
`ArticleParser`'s WKWebView). Leave it as a real app UA. *(Wave 1 update: we
send an **explicit** descriptive UA on reddit.com requests —
`ios:com.ellenbartling.readlater:v0.1 (Read Later RSS)` — rather than relying on
the CFNetwork default, so the identity is unique and stable across OS versions.)*

**Architecture friction:** `FeedRefresher.refreshAll` fans out all feeds
concurrently via `TaskGroup`. Two+ Reddit subs from one IP = instant 429s. See
open question 2.

## 2. Fit with the Feed/FeedEntry model

Subscribing works unchanged: Reddit's Atom parses cleanly through the existing
delegate — `<title>`, `<link rel="alternate" href>`, `<id>` (`t3_…`),
`<updated>`/`<published>`, `<content type="html">` → `plainSummary`. What breaks
is *what the fields mean*:

- **`entry.url` = the comment permalink** (`…/comments/{id}/{slug}/`), not the
  target article. This is the tap target today → wrong destination.
- **`entry.summary`** is the escaped content HTML reduced to text: for link
  posts a `submitted by … [link] [comments]` stub; for self posts, the actual
  post body. Usable as-is for the row; not the read target.
- **No field carries the external article URL** — it lives only as an
  `<a href>` inside `<content>`.

## 3. The link-post problem (the crux)

A Reddit link-post entry has three plausible "read" targets: the external
article, the comment thread, or both. Reddit self-posts have only the body.
`ArticleParser` on a Reddit permalink yields garbage (confirmed assumption:
comment pages are SPAs Readability can't extract).

**Recommendation (v1):**

- **Link posts → parse the external URL.** Add Reddit-awareness that pulls the
  first non-reddit `<a href>` out of `<content>` and routes *that* through the
  normal `PendingSave → ArticleParser → Article` pipeline. Real article, full
  reader/highlight/TTS support — exactly what a read-later app wants.
- **Self posts → render the feed HTML, don't fetch the page.** `PendingSave`
  already carries `capturedHTML`, and `PendingSaveIngest` threads it into
  `ArticleParser.parse(url:prefetchedHTML:)`. Pass the entry's `<content>` HTML
  as `capturedHTML` so Readability runs on the post body we already have instead
  of the SPA. URL stays the permalink (canonical identity + dedup).
- **Discussion link:** keep the comment permalink reachable from the Article as
  a "View discussion on Reddit" affordance. v1 can stash it; the reader-side
  button is a small follow-up (see scope).

**Model change (CloudKit-safe).** Add one optional field to `FeedEntry`:

```swift
var externalURL: URL?   // link posts: the target article; nil for self posts
```

Optional satisfies the CloudKit invariant (attributes optional-or-defaulted).
`isRedditSelfPost` is then just `externalURL == nil`. On tap:
`PendingSave(url: externalURL ?? entry.url, capturedHTML: selfPost ? contentHTML : nil, source: .rss)`.
The comment permalink (`entry.url`) is preserved for the discussion link. No
`Article` schema change needed for v1 if the discussion button is deferred;
otherwise add a matching optional `discussionURL: URL?` to `Article`.

Detection stays localized: a `RedditFeed` shim keyed off `feedURL.host` ==
`reddit.com`/`www.reddit.com`/`old.reddit.com` populates `externalURL` +
`contentHTML` during `merge`. The generic parser and non-Reddit feeds are
untouched.

## 4. Subreddit subscription UX

- **Accept `r/ios` shorthand.** Extend `FeedsView.normalizedURL`: a
  `^/?(r|u|user)/…` string (no dot/scheme) expands to
  `https://www.reddit.com/{…}/.rss`. Bare `reddit.com/r/ios` links already
  resolve via existing discovery. Low cost, high delight.
- **Sort variants:** keep **URL-literal for v1** — power users paste
  `/top.rss?t=week`; shorthand defaults to hot. A sort picker (hot/new/top-week)
  is v2 polish, not worth the picker UI now.
- Feed title comes free from the Atom `<title>` (`"reddit.com: r/ios"`).

## 5. Scope cut

**v1 (small, ships the feature):** `externalURL` field + `RedditFeed` shim
(external-link extraction, self-post `capturedHTML` routing) + `r/…` shorthand.
Effort: ~a day. Reuses the entire existing pipeline; the net new surface is one
model field, one ~80-line shim, and a shorthand branch.

**v2 (nice-to-have):** "View discussion" button in the reader (`discussionURL`
on `Article`); sort picker; the `user=`/`feed=` rate-limit escape hatch as a
Settings field; sequential (non-concurrent) refresh for reddit.com hosts.

**Explicitly out:** comment-thread *reading* (rendering the discussion as an
article), Reddit login/OAuth, `.json` anything.

## 6. Resolved decisions (Ellen)

1. **Self-post rendering** → parse the feed `<content>` HTML in-app (no extra
   fetch). Persisted on `FeedEntry.contentHTML` for self posts and routed as
   `PendingSave.capturedHTML`.
2. **429 handling** → serialize + space reddit.com refreshes and send a
   descriptive User-Agent; back off (keep existing entries) on 429. The
   `user=`/`feed=` escape hatch is **not** built (revisit in wave 2 if needed —
   wave 2's authenticated JSON path largely obviates it).
3. **Discussion link** → **built in wave 1.** `Article.discussionURL` (generic,
   not Reddit-named) + a reader affordance + an "Open discussions in" setting.
4. **Shorthand scope** → **`r/…` only** for wave 1. `u/…` user feeds and
   multireddit `r/a+b` are deferred (they still work if pasted as full URLs).

---

## Wave 1 as built

- **`FeedEntry.externalURL: URL?`** — CloudKit-safe optional. Populated at merge
  time for Reddit feeds only, by extracting the `[link]` footer anchor from the
  entry's content HTML when it differs from the `[comments]` anchor; nil for
  self posts and every non-Reddit feed. **`FeedEntry.contentHTML: String?`**
  persists the raw self-post body HTML (capped at 100k chars) so it renders
  through the prefetched-HTML path without a re-fetch; link posts store nil.
- **Reddit Atom shape** (distilled from a live `r/swift/.rss`): every `<entry>`
  has `<link href>` = the comments permalink, `<id>t3_…</id>`, and a
  `<content type="html">` whose footer carries `<a…>[link]</a>` and
  `<a…>[comments]</a>`. Link vs self is decided by comparing those two hrefs
  (equal → self; different → link, and `[link]` is the external URL, which may be
  an article, an `i.redd.it` image, or a cross-posted reddit thread).
- **Tap behaviour** (`FeedEntriesView.open`): `entry.url` stays the permalink in
  both cases. Link post → `PendingSave(url: externalURL, discussionURL:
  permalink)`, no captured HTML → normal parse of the external article. Self
  post → `PendingSave(url: permalink, discussionURL: permalink, capturedHTML:
  contentHTML, title: postTitle)` → Readability over the post body.
- **Discussion affordance:** `Article.discussionURL` carries the permalink
  (threaded via `PendingSave.discussionURL` → `PendingSaveIngest`). The reader
  shows a toolbar button when present; tapping honours the **Open discussions
  in** setting (System Default → `UIApplication.open` on reddit.com; Narwhal →
  `narwhal://open-url/<encoded>` when `canOpenURL` finds it, else fall back;
  In-App Browser → `SFSafariViewController`). Long-press always offers **Open in
  Browser**.
  - **Narwhal scheme verdict: confirmed.** Narwhal 2 registers `narwhal://` and
    opens arbitrary reddit URLs via `narwhal://open-url/<encodeURIComponent(url)>`
    (verified against the community "Rewrite reddit links to use the Narwhal 2
    URI scheme" userscript). `narwhal` is added to `LSApplicationQueriesSchemes`
    via project.yml (never the .xcodeproj).
- **`r/name` shorthand:** `r/ios`, `/r/ios`, `reddit.com/r/ios`,
  `www.reddit.com/r/ios` (± trailing slash) → `https://www.reddit.com/r/ios/.rss`.
  Sort variants, explicit `.rss`, query strings, and full URLs pass through
  URL-literal.
- **Refresh serialization:** `FeedRefresher.refreshAll` partitions by host —
  non-Reddit stays concurrent; reddit.com-family fetch sequentially with
  `RedditPolicy.refreshSpacing` (2s) between requests and a descriptive
  `User-Agent`. On HTTP 429 (`FetchError.rateLimited`) the sequential loop backs
  off and stops; remaining Reddit feeds keep their existing entries.

## Wave 2 — "Sign in with Reddit"

**Status: built** (branch `claude/reddit-oauth`; see "Wave 2 as built" below).
Live use is blocked on one step: registering the Reddit installed app at
reddit.com/prefs/apps (redirect URI `readlater://oauth/reddit`) and pasting the
client ID into `RedditAuthConfig.clientID` — the single config point. While it
is empty the entire feature hides itself.

Approved in principle. Installed-app OAuth (PKCE, no client secret), run
entirely phone-side:

- **mysubreddits import checklist** — pull the signed-in user's subscriptions and
  offer them as a subscribe checklist.
- **Saved-posts IMPORT** — materialize the user's Reddit *saved* history as
  Articles. Framed as an **escape pod** for that history: get it out of Reddit
  and into a durable, highlightable, exportable library.
- **Save-back action in the reader** — save an article's discussion back to the
  user's Reddit saved list.
- **JSON listings replace RSS for signed-in refresh** — authenticated `.json`
  endpoints (higher limits, richer data) supersede the anonymous RSS path once
  signed in.

**Risk posture.** Per-user OAuth calls made from the user's own phone sit
squarely in Reddit's free tier (no server, no shared app-wide quota). RSS stays
the graceful-degradation path if OAuth is unavailable or the user is signed out.
Keep the Reddit client **thin and isolated behind a protocol** so the RSS and
JSON backends are swappable and the OAuth surface stays contained.

## Wave 2 as built

- **OAuth**: authorization-code + PKCE (S256) for an installed app, via
  `ASWebAuthenticationSession` (sanctioned OAuth surface, deliberately distinct
  from the cookie-based site logins — rationale documented in
  `RedditOAuth.swift`). `duration=permanent` for a refresh token; scopes
  `identity mysubreddits history save read`. Tokens live in Keychain
  (`RedditTokenStore`, one JSON blob over `KeychainStore`), refreshed
  transparently with 60s leeway and once-on-401. Descriptive UA
  (`ios:com.ellenbartling.readlater:v0.1.0 (personal read-later app)`) on every
  oauth.reddit.com call.
- **Client**: `RedditAPIClientProtocol` (account / subscribed subreddits /
  saved posts / save / revoke) with one concrete `RedditAPIClient` —
  rate-limit-respectful (honors `x-ratelimit-*`, backs off + retries once on
  429), pagination capped at 50 pages. Pure transforms live in
  `RedditParsing` / `RedditImportPlan` (fullname derivation, self-vs-link
  routing, dedupe) and carry the unit tests, since live OAuth can't be
  exercised without a client ID.
- **Subreddit import**: Settings → Reddit Account → Import Subreddits.
  Checklist (none pre-checked, Select All), subscribes via wave-1 `Feed` rows
  keyed on the sub's `.rss` URL; entries populate on the next spaced refresh
  (no burst of reddit.com fetches at import time).
- **Saved-posts import**: Settings → Reddit Account → Import Saved Posts. Caps
  at 300 newest; saved comments skipped; link posts `PendingSave` the external
  URL, self posts route decoded `selftext_html` through the prefetched-HTML
  path; permalink → `discussionURL`; dedupe by normalized URL against existing
  Articles and within the batch. Parses queue on the existing single-slot
  serial parse chain (`PendingSaveIngest`) — stubs appear immediately,
  parse-on-open covers the long tail. New `PendingSave.Source.reddit`.
- **Save-back**: reader → discussion button context menu → "Save to Reddit"
  (only for reddit-host `discussionURL` while signed in); fullname derived from
  the permalink (`t3_<id>`), `POST /api/save`.
- **Signed-in surfacing**: Settings → Reddit section shows the account row
  (`u/name`) with the connected identity, imports, and Sign Out (server-side
  token revoke + Keychain purge).
- **Not done (deliberate)**: JSON listings replacing RSS for signed-in feed
  refresh — the RSS path remains the refresh surface for now; the client
  protocol is the seam a future listing backend plugs into.
