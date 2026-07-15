# Reddit via RSS — design

Status: **proposed** — doc-only, for Ellen's review. No code on this branch.
Owner file set (when built): `Shared/Models/FeedEntry.swift`,
`ReadLater/Services/Feeds/` (parser + fetcher + a new Reddit shim),
`ReadLater/Features/Feeds/FeedsView.swift`. Builds on the existing Feeds
feature (branch `claude/features-backlog-priorities-xuhej5`).

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
`ArticleParser`'s WKWebView). Leave it as a real app UA.

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

## 6. Open questions for Ellen

1. **Self-post rendering** — parse feed `<content>` HTML (my rec, no extra
   fetch, offline-friendly) vs. just keep a "Open in Reddit" bounce for
   self-posts in v1? The former is more work but keeps everything in-app.
2. **429 handling** — accept the throttle in v1 (stale feeds degrade gracefully;
   existing entries survive a failed fetch) and only serialize/space-out
   reddit.com refreshes, or build the `user=`/`feed=` param escape hatch now?
3. **Discussion link in v1 or v2?** It needs an `Article` field; cheap to add
   now while we're touching the schema, vs. deferring the whole thing.
4. **Shorthand scope** — `r/…` only, or also `u/…` user feeds and multireddit
   `r/a+b` in the first cut?
