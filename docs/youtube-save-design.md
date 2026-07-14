# Save from YouTube (with transcript) — design

Status: **draft for Ellen's review** — this is a design, not an implementation.
Decision-shaped questions are collected under "Open questions" at the end.
Touches (when built): a new `ReadLater/Services/Parsing/` sibling to
`ArticleParser`, a small `Shared/` URL helper, and additive fields on
`Article`/`ArticleBlock`. Reuses the existing `Parsed` → `Article.apply` seam so
the reader, highlighting, TTS, and image cache need no changes for v1.

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
  available — watch on YouTube." Never fail the save. (Whether to add a keyed
  third-party API as a second-tier fallback is Open Q1.)

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
- **TTS interplay:** reading a transcript aloud in a synthetic voice while the
  creator's *actual narrated audio* is one tap away is the worse experience.
  Recommended default: **keep TTS available** (a transcript is just text) but
  **de-emphasize it for video articles** and foreground "Watch on YouTube"
  instead. (Confirm — Open Q3.)

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

## Scope cut

**v1 — smallest lovable (moderate effort).** URL detection + `VideoArticleParser`
+ desktop-UA load + `captionTracks` scrape → title, channel (`author`),
thumbnail (`heroImageURL`), description, and transcript as plain `.paragraph`
blocks. No timestamps, no speaker turns. Graceful metadata-only fallback when no
transcript. Reuses `Parsed`/`apply`/blocks/reader/highlight/TTS untouched. The
bulk of the work is one new service and getting the scrape robust.

**v2 — timestamps & seek (larger effort).** Add optional `startMS` to
`ArticleBlock`, tap-to-seek deep links, coalescing tuning, video badge in the
Library, and (if chosen) a keyed third-party fallback. The schema and reader
touches make this the heavier cut; keep it separate.

## Open questions for Ellen

1. **Fallback tier.** When the in-app scrape yields nothing (no captions or a
   PoToken-gated empty body), do we (a) save metadata-only with a "no
   transcript" note — fully local, or (b) also allow a keyed third-party
   transcript API that sends saved video IDs off-device? (a) is the privacy
   default; (b) recovers more videos at the cost of a key + data leaving the
   device.
2. **Timestamps: v1 or v2?** Deferring keeps v1 to zero schema change. Pulling
   `startMS` into v1 means adding the optional field now (safe) but tuning
   coalescing/seek up front. How much do you want tap-to-seek on day one?
3. **TTS default for videos.** Keep TTS a co-equal action, or de-emphasize it in
   favor of "Watch on YouTube" as recommended above?
4. **Library distinction.** Should video articles read as normal articles in the
   Library, or carry a play glyph / duration badge / channel-as-author so
   they're scannable as video?
