# Article Blocks — Architecture Plan

**Date:** 2026-07-11  
**Status:** Approved for future implementation (not started)  
**Approach:** Incremental migration from TextKit (`UITextView` + `plainText`) to a native block-based reader, preserving highlight/TTS/Obsidian behavior at each step.

## Problem

The reader today renders a single `plainText` string in `HighlightableTextView`. That works well for highlighting (UTF-16 offsets from `UITextView.selectedRange`) but limits what we can show:

- **Images** disappear (Readability keeps them in `extractedHTML`, not `textContent`).
- **Video embeds** (YouTube, Vimeo, etc.) cannot play inline in the scroll surface.
- **Tables, code blocks, and rich embeds** require bespoke handling or a web renderer rewrite.

We fixed the immediate **gap bug** (2026-07-11) by deriving clean paragraph text from Readability's block HTML instead of raw `textContent`. That unblocks readable articles now without changing the highlight model.

This document plans the **next evolution**: typed article blocks with a native block renderer, without a WKWebView reader rewrite.

---

## Goals

- Render images, video embeds, and other non-text content in reading flow.
- Keep **native** selection, instant highlight, edit menus, TTS paragraph sync, and scroll progress.
- Preserve existing highlights across renderer upgrades (re-parse, layout changes).
- Support future **YouTube-as-transcript** saves using the same block types.
- Stay on iOS 17+, Swift 5.10, `@Observable`, no `NavigationView`.

## Non-goals (initial block pass)

- Full-fidelity HTML/CSS (that's the WKWebView fork — explicitly not this plan).
- Cross-block continuous text selection on day one (hard; may ship text-only articles in single-block mode first).
- LaTeX, interactive charts, or arbitrary iframe embeds beyond a curated set.
- Re-parsing every existing article automatically (opt-in or lazy on open).
- CloudKit schema migration for blocks in v1 (local JSON blob on `Article` first).

---

## Guiding principles

1. **`plainText` remains the highlight coordinate space** until block-native anchors are proven. Even with blocks, derive `plainText` by concatenating text-bearing blocks with `\n\n` separators (same as today's gap fix).
2. **`quotedText` is the long-term source of truth** for highlight location. Offsets are a cache; prefix/suffix context (TextQuoteSelector-style) makes anchors survive renderer and re-parse changes.
3. **Parse once, store structure.** Block JSON is canonical for layout; `plainText` and `extractedHTML` are derived/cache fields.
4. **Ship incrementally.** Each phase delivers user-visible value; no big-bang rewrite.

---

## Block type catalog

### Phase 1 — Reader-visible (high value)

| Type | Source in HTML | Render | Highlight impact |
|------|----------------|--------|------------------|
| `paragraph` | `<p>`, leaf text blocks | Text | Yes — contributes to `plainText` |
| `heading` | `<h1>`–`<h6>` | Styled text | Yes |
| `listItem` | `<li>` | Bulleted/numbered text | Yes |
| `blockquote` | `<blockquote>` | Indented text | Yes |
| `preformatted` | `<pre>`, `<code>` blocks | Monospace, preserve whitespace | Yes |
| `image` | `<figure>`, `<img>` | Native image view + optional caption | No text; does not advance `plainText` offset |
| `caption` | `<figcaption>` | Smaller text below image | Yes (often merged into image block) |
| `divider` | `<hr>` | Hairline | No |

### Phase 2 — Embeds & media

| Type | Source | Render | Notes |
|------|--------|--------|-------|
| `videoEmbed` | `<iframe>` (YouTube/Vimeo), oEmbed patterns | Poster + tap-to-play; inline player in block | Provider enum + video ID; player is child `WKWebView` or sheet |
| `audioEmbed` | `<audio>` | Native controls or tap-to-play | |
| `pullQuote` | styled `<blockquote>` / aside | Distinct styling | Yes |

### Phase 3 — Structured content

| Type | Source | Render | Notes |
|------|--------|--------|-------|
| `table` | `<table>` | Native grid or scrollable table view | Highlighting limited to cell text |
| `codeBlock` | `<pre><code class="language-x">` | Monospace + optional syntax tokens | Yes |
| `tweetCard` | Twitter blockquote embed | Native card (oEmbed API) | Tap opens in Safari |

### YouTube save pipeline (separate ingest)

| Type | Source | Render |
|------|--------|--------|
| `videoEmbed` | YouTube URL / share | Top-of-article player block |
| `transcriptSegment` | Caption track | Timestamped paragraph blocks |

Transcript blocks carry `startTime` / `endTime` for seek-on-tap and TTS-style follow-along (reuse `currentSpokenRange` driven by player time instead of TTS index).

---

## Data model

### `ArticleBlock` (Codable, stored on `Article`)

Add to [`Article`](Shared/Models/Article.swift):

```swift
// JSON-encoded [ArticleBlock]; CloudKit-safe optional blob.
var blocksJSON: Data?
var blocksVersion: Int = 0  // schema version for migrations
```

Keep existing fields during transition:

- `plainText` — derived from text blocks (highlight offset space).
- `extractedHTML` — raw Readability output (debug/fallback).

### Block schema (v1)

```swift
struct ArticleBlock: Codable, Identifiable {
    var id: UUID
    var type: BlockType
    var text: String?           // paragraph, heading, listItem, blockquote, pre, caption
    var level: Int?             // heading 1–6, list nesting
    var src: URL?               // image
    var alt: String?            // image alt / accessibility
    var width: Int?             // image intrinsic width (aspect ratio)
    var height: Int?
    var provider: VideoProvider? // youtube, vimeo, unknown
    var embedID: String?        // provider video id
    var embedURL: URL?          // canonical watch URL
    var startTime: Double?      // transcript segment start (seconds)
    var endTime: Double?        // transcript segment end
    var listStyle: ListStyle?   // ordered, unordered
}

enum BlockType: String, Codable {
    case paragraph, heading, listItem, blockquote, preformatted
    case image, videoEmbed, audioEmbed, divider, table, codeBlock
    case transcriptSegment
}
```

`plainText` derivation:

```
textBlocks = blocks where type contributes text
plainText = textBlocks.map(\.text).joined(separator: "\n\n")
```

Non-text blocks (image, video, divider) are **not** represented in `plainText` — highlights never anchor inside them.

### Highlight anchor evolution (v2, optional)

Extend [`Highlight`](Shared/Models/Highlight.swift) when block renderer ships:

| Field | Purpose |
|-------|---------|
| `prefixContext` | ~32 chars before `quotedText` (TextQuoteSelector) |
| `suffixContext` | ~32 chars after |
| `blockID` | Optional — block containing highlight start |

`HighlightAnchor.locate` order: exact offsets → quote + context → quote alone → collapsed whitespace (existing).

Existing highlights without context fields continue to work via `quotedText` search.

---

## Parser pipeline

Extend the JS block walk already in [`ArticleParser`](ReadLater/Services/ArticleParser.swift) (gap fix, 2026-07-11):

```
Readability.parse()
  → article.content (HTML)
  → walk DOM → [ArticleBlock]   // NEW: typed blocks, preserve order
  → derive plainText from text blocks
  → return Parsed(blocks, plainText, extractedHTML, …)
```

### Embed detection (JS, same pass)

- **Images:** `<img src>`, `<figure>` with `<img>` + optional `<figcaption>`.
- **YouTube:** `iframe[src*="youtube.com/embed"]`, `youtu.be` links, `data-youtube-id`.
- **Vimeo:** `iframe[src*="player.vimeo.com"]`.
- Resolve relative URLs against article base URL.

### Telemetry (optional, low cost)

Log counts at parse time: `{ paragraphs, images, videoEmbeds, tables }`. Informs whether Phase 2/3 is worth prioritizing. No user-visible change.

---

## Reader architecture

### Current (TextKit era)

```
ReaderView
  └── HighlightableTextView (UITextView)
        plainText + highlight offsets
```

### Target (block era)

```
ReaderView
  └── BlockReaderView (ScrollView or UICollectionView)
        ForEach(blocks) { block in
          switch block.type {
            case .paragraph, .heading, … → TextBlockView (selectable)
            case .image → ImageBlockView
            case .videoEmbed → VideoEmbedBlockView
            …
          }
        }
        + BlockSelectionCoordinator (highlight creation across text blocks)
```

### TextKit bridge (Phase 1b — optional middle step)

Before full block UI, render images via `NSTextAttachment` in the existing `UITextView`:

- Parser emits image positions relative to text block index.
- Renderer splices attachments between text segments.
- **`plainText` stays text-only**; attachment positions are render-only (not in offset space).

This ships images faster but adds segment-map complexity. Skip if block UI is close; do if images are urgent.

### Video block UX

1. **Collapsed:** poster frame (oEmbed thumbnail or first frame) + play affordance + provider badge.
2. **Expanded (tap):** inline `WKWebView` with provider iframe *or* promote to floating mini-player (reuse future audio player chrome).
3. **No autoplay** in scroll surface (battery, UX, App Store norms).

YouTube **saved-as-transcript** uses the same `videoEmbed` block at top; transcript segments are `transcriptSegment` blocks below.

---

## TTS & scroll progress

| Feature | TextKit today | Block future |
|---------|---------------|--------------|
| TTS paragraph index | Split `plainText` on `\n` | Same — `plainText` derived from blocks |
| Spoken paragraph tint | `currentSpokenRange` in `HighlightableTextView` | Map paragraph index → block ID + in-block range |
| Scroll progress | `scrollViewDidScroll` on UITextView | Aggregate block heights in block scroll view |
| Transcript sync | N/A | Player time → segment with matching `startTime`/`endTime` → tint block |

---

## Obsidian export

[`ObsidianExporter`](ReadLater/Services/Export/ObsidianExporter.swift) today writes highlights against `plainText`. No change required for Phase 1.

Future enhancement: emit images as `![alt](src)` and video embeds as `[Watch](url)` in the `%% readlater:start %%` region when blocks exist. Deterministic rendering preserved.

---

## Migration strategy

### Existing articles

| Scenario | Behavior |
|----------|----------|
| Old article, no `blocksJSON` | Reader uses `plainText` + TextKit (current path) |
| Re-saved / re-parsed | Parser fills `blocksJSON` + refreshed `plainText` |
| Highlights after re-parse | `HighlightAnchor` re-anchors via `quotedText` (existing) |

Optional **"Re-extract"** action in reader overflow menu (lazy migration).

### Renderer selection

```swift
var readerMode: ReaderMode {
    if article.blocksJSON != nil { return .blocks }
    return .textKit  // legacy
}
```

Feature flag in `AppSettings` for dogfooding block reader before default flip.

---

## Phased delivery

### ✅ Phase 0 — TextKit gap fix (done 2026-07-11)

- Derive `plainText` from block-level HTML walk, not raw `textContent`.
- Fixes whitespace gaps; images still absent.

### Phase 1a — Parse & store blocks (no UI change)

- Extend JS walk to emit `[ArticleBlock]` JSON.
- Store `blocksJSON` on `Article`; derive `plainText` from text blocks.
- Unit-test block extraction with fixture HTML strings (no WKWebView).
- Verify `plainText` matches TextKit output for text-only articles.

### Phase 1b — Images (choose one)

- **Option A:** `NSTextAttachment` in existing `HighlightableTextView` (faster).
- **Option B:** Skip to Phase 2 if block UI is ready soon.

Add `ArticleImageCache` (URLSession → memory + disk, size to container width).

### Phase 2 — Block reader UI

- `BlockReaderView` + per-type block views.
- Text blocks: start with **one `UITextView` per paragraph** (simple selection within block) OR a single concatenated view for text-only articles.
- Image + divider blocks between text.
- Feature flag; TextKit fallback for articles without blocks.

### Phase 2b — Video embed blocks

- `VideoEmbedBlockView` (poster + tap-to-play).
- oEmbed/thumbnail resolution service.
- Inline iframe optional (Phase 2b+).

### Phase 3 — Highlight anchor v2

- Add `prefixContext` / `suffixContext` on new highlights.
- Backfill optional; old highlights keep working.

### Phase 4 — Cross-block selection

- Custom selection coordinator spanning adjacent text blocks.
- Required for "select across paragraph boundary" parity with today's single `UITextView`.

### Phase 5 — YouTube ingest

- New save pipeline: URL → metadata + caption track → `[videoEmbed, transcriptSegment…]`.
- Player + transcript sync (reuse TTS scroll/tint machinery).

---

## Prep work during TextKit era (no reader changes)

These can land anytime without flipping the renderer:

1. **Block extraction in parser** + `blocksJSON` storage (Phase 1a).
2. **Parse-time embed/image metadata** even if not rendered.
3. **Stronger highlight context** on create (`prefixContext` / `suffixContext`).
4. **Content-type telemetry** at parse time.
5. **Fixture HTML tests** for block extractor.

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Cross-block selection is hard | Ship per-block selection first; text-only articles stay one view |
| `blocksJSON` bloats CloudKit records | Compress JSON; cap image URLs not bytes; sync blocks lazily if needed |
| Re-parse shifts highlight offsets | `quotedText` + context re-anchor (already partially built) |
| Inline video memory/scroll jank | Poster-by-default; one active player; pause on scroll off-screen |
| YouTube captions API fragility | Abstract `TranscriptProvider`; multiple backends |

---

## What we are NOT doing

- **WKWebView reader** — different anchor model, full highlight engine rewrite. Remains an escape hatch if block ceiling is hit, not the planned path.
- **Storing highlight offsets in attachment character space** — attachments are render-only; offsets stay in text-only `plainText`.

---

## Success criteria

- [ ] New saves: no whitespace gaps; images visible in reader.
- [ ] Existing highlights survive re-parse of same article (manual QA + `HighlightAnchor` tests).
- [ ] Video embed in article: poster visible, tap plays, scroll performance acceptable.
- [ ] YouTube transcript save: highlight + tap-to-seek works on transcript text.
- [ ] Obsidian export unchanged for text-only; images optionally exported in v2.

---

## Related files

| File | Role |
|------|------|
| [`ArticleParser.swift`](ReadLater/Services/ArticleParser.swift) | Block extraction, plainText derivation |
| [`Article.swift`](Shared/Models/Article.swift) | `blocksJSON`, `plainText`, `extractedHTML` |
| [`Highlight.swift`](Shared/Models/Highlight.swift) | Anchor fields |
| [`HighlightAnchor.swift`](ReadLater/Services/Highlighting/HighlightAnchor.swift) | Re-anchoring logic |
| [`HighlightableTextView.swift`](ReadLater/Features/Reader/HighlightableTextView.swift) | Current TextKit renderer |
| [`ReaderView.swift`](ReadLater/Features/Reader/ReaderView.swift) | Reader shell, TTS, chrome |

---

## Open questions (decide before Phase 2)

1. **CollectionView vs LazyVStack** for block scroll — perf vs simplicity.
2. **Image caching** — URLCache only vs dedicated disk cache with size limits.
3. **Re-parse policy** — on save only, on open, or user-triggered?
4. **Block reader default flip** — all new articles, or feature flag until Phase 4 selection ships?
