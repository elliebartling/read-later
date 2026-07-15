# Save from YouTube (with transcript) — design

Status: **approved by Ellen (2026-07-14)** — her answers to the review
questions are recorded under "Review decisions" below, plus one approved scope
addition: **channel subscriptions** as a third tenant of the Feeds
architecture. Touches (when built): a new `ReadLater/Services/Parsing/`
sibling to `ArticleParser`, a small `Shared/` URL helper, additive fields on
`Article`/`ArticleBlock`/`FeedEntry`, and the add-feed flow. Reuses the
existing `Parsed` → `Article.apply` seam so the reader, highlighting, TTS, and
image cache need no changes for v1.

## Problem

A YouTube link is a first-class "read later" item — a talk, a tutorial, a
podcast — but today it degrades badly. `PendingSaveIngest` hands the URL to
`ArticleParser`, which loads `youtube.com/watch` in the off-screen WKWebView and
runs Readability on YouTube's JS app shell. The result is a link-dense nav
husk that the quality gate rejects: the save lands as `parseStatus == .failed`,
or (worse) persists as junk. We want a YouTube save to become a real article:
**title, channel, thumbnail, and — when available — the transcript as readable,
highlightable blocks.**

## Non-negotiable constraint: transcript acquisition is adversarial

Everything downstream (data model, reader) is easy. The hard part — and the part
that decides whether this ships — is *getting the transcript at all*. The
honest landscape as of mid-2026:

| Approach | Verdict | Why |
|----------|---------|-----|
| **Official Data API** (`captions.download`) | **Dead end** | Requires OAuth *and* the caller must own the video. There is no official way to fetch a third party's public transcript. 200 quota units/call, needs an API key. Useless for saving other people's videos. |
| **`timedtext` endpoint direct** | **Fragile** | Undocumented. Now needs an Innertube `youtubei/v1/player` call to mint the caption `baseUrl`, and tracks increasingly carry `&exp=xpe` (a PoToken gate) that returns an empty `200` to any programmatic request — even one with logged-in cookies. Breaks every few months. |
| **yt-dlp-style extraction** | **Not viable on iOS** | It's a Python/binary tool that shells out and self-updates against YouTube's churn. No subprocess on iOS; App Store rules and the update cadence make it a non-starter. |
| **On-device STT** (`SFSpeechRecognizer` / iOS 26 `SpeechTranscriber`) | **Blocked upstream** | The recognizer is fine; the blocker is *audio access*. We'd first have to download the video/audio stream — i.e. the yt-dlp problem above, plus ToS exposure. Not a real fallback. |
| **In-WebView caption scrape** | **Best fit** | Reuse the WKWebView we already run: load the watch page with a **desktop** UA, read `ytInitialPlayerResponse.captions…captionTracks[].baseUrl` out of the live page, and fetch the `json3` transcript *from inside the page's own JS context* — where YouTube's session (and any PoToken the real player generated) already exists. |
| **Third-party transcript API** (keyed) | **Possible fallback** | Services that resolve the PoToken problem server-side. Costs money, needs a key in `KeychainStore`, and **sends the video IDs you save off-device** — a privacy regression for an otherwise-local app. See Open Q1. |

**What the share sheet actually hands us:** when you Share from the YouTube iOS
app or Safari, the payload is *just a URL* — `https://youtu.be/<id>?si=<tracking>`
(or a `watch?v=` link). No HTML, no transcript, no `capturedHTML`. So the
transcript work happens entirely in the main app at parse time; the extension
path is unchanged.

### Recommended strategy

- **Primary:** in-WebView scrape. Detect a YouTube URL, load the watch page in
  the existing off-screen WKWebView with a **desktop** Safari UA (the mobile UA
  gets `m.youtube.com`, which lacks the transcript surface), read
  `captionTracks` from `ytInitialPlayerResponse`, pick the track (prefer
  manual > English auto > first), and fetch its `baseUrl&fmt=json3` via an
  in-page `fetch()`. Parse the cues to text.
- **Failure modes & fallback:** no captions on the video, a PoToken-gated empty
  body, or a layout change → **degrade gracefully to a metadata-only save**
  (title + channel + thumbnail + description) with a reader note "No transcript
  available — watch on YouTube." Never fail the save. Per review decision 3
  there is **no third-party-API tier** — metadata-only is the floor.

This strategy has one large virtue: it fails *soft* and it fails *offline to
us* — no keys, no accounts, no data leaving the device, and every piece reuses
infrastructure that already exists.

## Data model

A video fits `Article` cleanly. The transcript is just text-bearing blocks, so
`plainText` (the UTF-16 highlight offset space) is derived by the existing
`ArticleBlocks.derivePlainText` path and **highlighting works with zero changes**.

- **Blocks — v1:** render transcript segments as ordinary `.paragraph` blocks.
  Auto-captions arrive as short ~1–5s cues with no speaker labels; coalesce runs
  of cues into readable paragraphs (~a sentence-group / ~40–60 words per block,
  or split on caption gaps). No new `BlockType` → no cross-version decode hazard
  (see below).
- **Timestamps — v2:** add an **optional** `startMS: Int?` to `ArticleBlock`.
  This is JSON-additive and CloudKit-safe (old clients ignore the unknown key;
  new clients default it to `nil`), so it does **not** force a `blocksVersion`
  bump on its own. Prefer this over a new `.transcriptSegment` `BlockType`:
  adding an enum case *is* a breaking change, because `JSONDecoder` throws on an
  unknown raw value and `Article.blocks` returns `nil` for the whole array — an
  older device syncing a v2 video via CloudKit would lose all its blocks. If we
  ever add the case, bump `blocksVersion` and gate on all devices updated.
- **CloudKit invariants:** any field we add stays optional or inline-defaulted.
  A likely small set on `Article`: `isVideo: Bool = false` (or reuse a source
  enum), `videoID: String?`, `videoDurationSeconds: Int?`. All CloudKit-safe.
- **Thumbnail as hero:** set `heroImageURL` to
  `https://img.youtube.com/vi/<id>/maxresdefault.jpg` (fall back to
  `hqdefault.jpg`). `ArticleImageCache` already downloads/downsamples any URL, so
  the hero renders with no new code.

## Reader UX

- **Transcript as blocks:** flowed paragraphs, coalesced as above. **No speaker
  turns in v1** — auto-captions don't carry them and manual ones rarely do.
- **Highlighting:** unchanged. Transcript blocks are text-bearing, so they join
  into `plainText` and the UTF-16 offset space holds exactly as for articles.
  Both readers (plain + block) get it for free.
- **Watch affordance (v1):** a prominent "Watch on YouTube" button on the hero
  that opens `https://youtu.be/<id>` (or the `youtube://` app deep link).
- **Tap-timestamp-to-seek (v2):** with `startMS` per block, tapping a segment
  opens `https://youtu.be/<id>?t=<seconds>` at that moment. Cheap once v2 stores
  the offsets.
- **TTS interplay (decided):** reading a transcript aloud in a synthetic voice
  while the creator's *actual narrated audio* is one tap away is the worse
  experience. Per review decision 2: **TTS stays available** (a transcript is
  just text) but is **de-emphasized on video articles** — "Watch on YouTube"
  is the lead action.
- **Library distinction (decided):** per review decision 4, video articles
  carry a small badge (play glyph) in Library lists so they scan as video.
  v1 keeps it minimal; a duration badge can join in v2 once
  `videoDurationSeconds` is captured.

## Ingest flow

- **Detection:** a small pure `Shared/YouTubeURL.swift` helper recognizing
  `youtube.com/watch?v=`, `youtu.be/<id>`, `youtube.com/shorts/<id>`, and the
  `m.`/`www.` variants; it extracts the 11-char video ID and strips the `si`
  tracking param. Pure and unit-testable, no WebView.
- **Hook point:** branch at the top of `ArticleParser.parse(url:)` (or a thin
  `parseOne` pre-check in `PendingSaveIngest`). When the URL is a YouTube URL,
  delegate to a new `VideoArticleParser` that reuses the same single-slot
  WKWebView but runs the caption-scrape flow instead of Readability, and
  returns the **same `ArticleParser.Parsed` struct**. `Article.apply` and the
  `.ready`/`.failed` bookkeeping are then completely unchanged — the branch is
  invisible to everything downstream.
- **Serialization:** already handled — `VideoArticleParser` shares the one
  WKWebView, so it inherits the existing single-parse-at-a-time discipline.
- **Feed entries need no special plumbing:** opening a `FeedEntry` already
  writes a `PendingSave` (source `.rss`) and drains it. A channel-feed entry's
  URL *is* a watch URL, so it hits the same `YouTubeURL` detection and routes
  into `VideoArticleParser` like any other save. The feed→video path is
  ordinary URL-based routing — nothing to build.

## Channel subscriptions (approved scope addition)

YouTube channels become the **third tenant of the existing Feeds
architecture** (alongside RSS/Atom sites), because YouTube still publishes a
free, anonymous, quota-less feed per channel:
`https://www.youtube.com/feeds/videos.xml?channel_id=UC…` (Atom; parseable by
the existing `FeedParser`; ~15 most recent videos).

### Wave 1 — subscribe by URL/handle (ships with v1)

- **Add-feed accepts channel URLs and @handles.** `youtube.com/channel/UC…`
  maps directly to the feed URL. `youtube.com/@handle` (and bare `@handle`)
  needs a **handle → channel_id resolution**: fetch the channel page and parse
  the id out of the page metadata (`og:url` / canonical link / the
  `channelId` meta). This is honest scraping and **will be fragile** — YouTube
  can reshape that markup any time. Failure mode: the add-feed sheet falls
  back to asking for the full channel URL, which never needs resolution.
- **Entry thumbnails.** Channel feeds carry `media:group/media:thumbnail`.
  Add an optional `thumbnailURL: URL?` to `FeedEntry` (CloudKit-safe) and
  teach `FeedParser` the `media:` namespace; entry lists render the thumbnail
  via `ArticleImageCache`. Additive for ordinary RSS feeds (stays `nil`).
- **Tap-through:** as noted under Ingest, entries flow into
  `VideoArticleParser` via ordinary URL routing. Zero feed-specific video code.

### Wave 2 — one-time subscription import

Two import paths, shipped together; **no ongoing sync, no OAuth** in either:

- **Site-login scrape:** the user signs into YouTube in the existing
  `SiteLoginView` sheet; we then load `youtube.com/feed/channels` off-screen
  with the shared cookie store (`SiteLoginStore` — same contract the paywall
  path uses), parse the subscribed-channel list, and present a checkbox picker;
  selected channels are subscribed via their RSS feed URLs. This is **scraping
  logged-in markup and is the most brittle thing in this design** — it can
  break silently on any YouTube redesign. It is acceptable *only because it is
  a one-time import*: if it breaks, nothing already-imported is lost.
- **Google Takeout CSV (the robust fallback, ships alongside):** Takeout's
  YouTube export includes `subscriptions.csv` with channel ids — a stable,
  documented format. Import via the Files picker into the same checkbox picker.
- **Google OAuth: explicitly rejected.** The verification gauntlet (scopes
  audit, demo video, annual re-review) is disproportionate for a personal app,
  and it would be the only Google-account credential in the app.

### Risk posture

Mirrors the Reddit design: **RSS is the foundation** — anonymous, free,
unauthenticated, and the only piece that runs continuously. Anything derived
from the user's *account* is a one-time import with a file-based fallback. So
YouTube can only take away what YouTube itself provides (the channel feeds);
a markup change breaks an import flow, never the subscriptions themselves.

## Scope cut

Channels reframe this feature: YouTube isn't just a URL type the parser
tolerates, it's a **first-class source** feeding the river — which raises the
stakes on the metadata fallback (a subscribed channel's videos must *always*
save cleanly, transcript or not). The transcript scrape is unchanged as the
hard part.

**v1 — smallest lovable (moderate effort).** URL detection +
`VideoArticleParser` + desktop-UA load + `captionTracks` scrape → title,
channel (`author`), thumbnail (`heroImageURL`), description, and transcript as
plain `.paragraph` blocks — no timestamps, no speaker turns (review decision
1). Metadata-only fallback when no transcript. Library play-glyph badge.
**Plus Wave 1 channels:** add-feed accepts channel URLs/@handles,
`FeedEntry.thumbnailURL`, `media:` parsing. Reuses
`Parsed`/`apply`/blocks/reader/highlight/TTS untouched. The bulk of the work
is one new service, scrape robustness, and the add-feed/parser touches.

**v2 — timestamps, seek, import (larger effort).** Optional `startMS` on
`ArticleBlock`, tap-to-seek deep links, coalescing tuning, duration badge.
**Plus Wave 2 import:** site-login `feed/channels` scrape + checkbox picker +
Takeout CSV fallback. The schema, reader, and login-scrape touches make this
the heavier cut; keep it separate.

## Review decisions (Ellen, 2026-07-14)

1. **Timestamps: v2, not v1.** Plain `.paragraph` blocks in v1 exactly as
   recommended — zero schema change, no CloudKit decode hazard.
2. **TTS on video articles: de-emphasized.** "Watch on YouTube" is the primary
   affordance; TTS stays available but is not the lead action.
3. **Fallback tier: metadata-only, fully on-device.** No third-party
   transcript APIs — a privacy decision. Saved video IDs never leave the
   device.
4. **Library distinction: yes, small badge.** Video articles get a play-glyph
   badge in Library lists.
5. **Scope addition: channel subscriptions** (section above) — Wave 1 RSS
   subscribe in v1, Wave 2 one-time import in v2.
