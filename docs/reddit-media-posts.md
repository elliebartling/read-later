# Reddit media posts, and why the feed→reader open was slow

Issue #75. Ellen's build-44 review, in full: *"Parsing from feed takes a long
time, which makes it feel slow/clunky, and Reddit parsing doesn't work at all."*
Her screenshot is the reader's failure state on an `i.redd.it` URL.

Two defects, one root cause between them.

## 1. What Reddit's RSS actually carries

Every entry in `https://www.reddit.com/r/<name>/.rss` has the same `<content>`
shape — a two-cell table: a preview `<img>` wrapped in a link to the permalink,
then `submitted by /u/name`, a `[link]` anchor, and a `[comments]` anchor.

Captured live, 2026-08:

| Post kind | `[link]` target | Preview image in the entry | Body text |
|---|---|---|---|
| Self post | the permalink (== `[comments]`) | none | `<div class="md">…` |
| External link | `https://github.com/…` | sometimes | sometimes |
| **Image** | `https://i.redd.it/<id>.jpeg` | `preview.redd.it`, 640px, `crop=smart` | sometimes |
| **Gallery** | `https://www.reddit.com/gallery/<id>` | `preview.redd.it` cover, sometimes only 140px | sometimes |
| **Video** | `https://v.redd.it/<id>` (no extension) | `external-preview.redd.it` poster frame | rarely |
| **Crosspost** | the ORIGINAL post's permalink | the original's preview | the crosspost's own text |

In a 25-item `r/pics` pull, 19 were image posts and 6 were galleries; in
`r/oddlysatisfying`, 22 of 25 were `v.redd.it`. So on a picture subreddit,
essentially **every** item hit the broken path.

## 2. Root cause: an image post is structurally a link post

`RedditFeed.externalURL(fromContentHTML:)` calls a post a *link post* when
`[link]` differs from `[comments]`. That is true of image, gallery, video and
crosspost entries alike. `FeedRefresher.redditFields` therefore:

1. stored the asset URL as the entry's `externalURL`, and
2. **discarded the entry's `contentHTML`** ("link post: no body to keep") —
   throwing away both the preview image and, on the posts that had one, the
   post's own self-text.

Opening the entry then saved `https://i.redd.it/abc.jpeg` and handed it to the
article extractor. Mozilla Readability wants a document; on a JPEG there is no
`<article>`, no `<p>`, and no text. Three attempts, then "Couldn't parse this
page" — while the picture, the caption and the preview all sat in the store.

Galleries were worse than a clean failure: `reddit.com/gallery/<id>` is a real
HTML page, so extraction *succeeded* on Reddit's logged-out chrome. The reader
rendered the Snoo mascot and a giant upvote arrow as the article.

### The fix

A third classification. `RedditFeed.postKind` now answers `.selfPost`,
`.link(URL)`, or **`.captured(URL)`** — "this `[link]` is not a readable page:
render what we hold." Media assets, galleries, and Reddit-internal targets
(crossposts) are all `.captured`, so the entry keeps its body and opens under
its own permalink, exactly like a self post.

`MediaArticleParser` then builds the article in pure Swift — no WKWebView, no
Readability, no network:

- **Image** → a lead `.image` block pointing at the **full-resolution**
  `i.redd.it` asset (not the 640px `crop=smart` preview, which is a crop), plus
  the post's self-text, minus the syndication footer.
- **Video** → the `external-preview` poster frame, `mediaURL` = the `v.redd.it`
  URL, and a "Play video" toolbar affordance that hands it to the system.
- **Gallery** → the cover image, `mediaURL` = the gallery permalink, and a
  "See all images" affordance.

Routing happens in `ArticleParsing.parse`, keyed on the URL, so it also covers
saves that never touched a feed: the share sheet, the Safari extension, the
Reddit saved-posts import — and re-parses of articles the old routing already
spoiled, which is how Ellen's existing `.failed` items heal on reopen.

### No new `BlockType`

The lead media is an ordinary `.image` block. A new enum case would be a
cross-version hazard (an older device decoding an unknown `type` string drops
the block — see `docs/youtube-save-design.md`), so the media *identity* travels
as additive optional fields, `Article.mediaURL` / `mediaKindRaw`, beside the
blocks rather than inside them. Both are optional, keeping the CloudKit rule.

## 3. What is impossible before Reddit OAuth

Stated plainly, so nobody re-litigates it from the reader side:

- **Gallery members.** The RSS `<content>` contains exactly one `<img>`. The
  remaining images live in `media_metadata` on the post JSON, which needs the
  API. v1 shows the cover and links out. (`RedditAPIClient` exists for the
  saved-posts import; wiring gallery expansion to it is a later wave, and it
  only works for signed-in users.)
- **Gallery cover resolution.** Some covers arrive at `width=140`. The
  `preview.redd.it` URL is signed per parameter set (`s=…`), so rewriting
  `width` invalidates it. We must use the URL as given.
- **Video playback.** `v.redd.it/<id>` is a DASH manifest root; audio and video
  are separate tracks that need muxing. A poster frame plus a link out is the
  honest v1.
- **Crosspost originals.** Reddit serves a JS app shell to an off-Reddit fetch
  of any permalink, so chasing the original post's URL fails the same way our
  own permalink does. We render the crosspost's own preview and text.

## 4. The latency half

Measured on iPhone 17e / iOS 26.5, instrumented in `PendingSaveIngest.parseOne`
(`parse OK|failed in N ms` — the wall clock from the reader putting up its
spinner to having content). "Before" is `main` at f8b56b6; both runs are the
same `r/pics` and `r/oddlysatisfying` feeds, same posts.

| Open | Before | After |
|---|---|---|
| Image post (`i.redd.it/…jpeg`) | **8951 ms → "Couldn't parse this page"** | **7 ms → the photograph** |
| Gallery post (`reddit.com/gallery/…`) | 2226 ms → Reddit's Snoo mascot and a giant upvote arrow rendered as the article | 12 ms → the cover image + caption + "See all images" |
| Video post (`v.redd.it`) | same failure shape as image | 8 ms → poster frame + "Play video" |
| Short self post | WebView round trip, then the floor | 7 ms, identical output |

The image-post "before" is worth reading twice: nine seconds of spinner to
arrive at a failure, on the *most common* post type in a picture subreddit.
That is the whole of "takes a long time … and doesn't work at all".

### A pre-existing wart this makes newly visible

An AskHistorians post whose body is empty (the title IS the question) has a
captured body consisting of nothing but the syndication footer. PR #70's
`CruftFilter.trimmingTrailingBoilerplate` deliberately refuses to empty an
article, so the reader renders `submitted by /u/name [link] [comments]` as the
body. That is **unchanged** by this PR — on `main` the same post takes the slow
path to the same floor and the same output — but the fast path surfaces it in
7 ms instead of a couple of seconds, so it is easier to notice. Fixing it means
deciding what a title-only post should render (an empty reader? the title as a
heading?), which is a reader-side call, not a parser one.

Three targeted wins, no pipeline restructuring:

1. **Media posts never touch the WebView.** `MediaArticleParser` is pure, so
   the parse is arithmetic; the image bytes load later through
   `ImageBlockView`/`ArticleImageCache` like any other article image.
2. **Short captured fragments never touch the WebView.** Readability abandons
   any document under its 500-character threshold, so for a body shorter than
   that the round trip's outcome is decided before it starts: it ends at the
   captured floor (PR #70). `ArticleParser.parse` now returns that same floor
   immediately — output-identical, seconds earlier. A *substantial* fragment
   still takes the normal path; PR #70's counter-fixture stands.
3. **The parser WebView is prewarmed** at first drain (app launch), so the
   first real save doesn't also pay for launching a WebContent process.
   `parse` awaits the prewarm task before it loads, so a warm-up navigation can
   never resolve a real parse's continuation.

Deliberately **not** done: optimistic reader content (showing the RSS summary
and upgrading in place). It would fight the reading-position restore landed in
PR #69 — the restore resolves a saved UTF-16 offset against `plainText`, and
swapping `plainText` underneath a restored reader moves the user's place. With
wins 1 and 2 the Reddit cases are effectively instant anyway; an external link
post still needs a real page fetch, which no amount of UI optimism removes.
