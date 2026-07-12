# Article Blocks Phase 1a + 2 — Design

**Date:** 2026-07-12
**Status:** Approved (chat)
**Parent:** 2026-07-11-article-blocks-plan.md (architecture; this spec scopes the first shipped slice)
**Floor:** iOS 26.0 (per the 2026-07-12 floor bump — no availability gates needed)

## Scope

Phase 1a (parse & store typed blocks) + Phase 2 (native block reader UI) +
re-extract, with the three research-derived anchoring upgrades. **Excluded:**
video/audio embeds, tables, tweet cards, cross-block selection (Phase 4),
YouTube ingest, full diff-match-patch fuzzy matching (Phase 3 completes it).

Research verdict (2026-07-12, three-agent survey): no adoptable library exists
(Textual lacks hookable selection; lexical-ios stalled; Readium/NSAttributedString
are WebKit-backed); open-source readers all use WKWebView+JS, which would mean
rebuilding our working native highlight engine in JS. Build native. Re-evaluate
Textual if it ever gains custom edit-menu hooks.

## Data model

`Shared/Models/ArticleBlock.swift` (new):

```swift
struct ArticleBlock: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: BlockType
    var text: String?        // all text-bearing types (incl. caption)
    var level: Int?          // heading 1–6
    var src: URL?            // image
    var alt: String?         // image accessibility
    var width: Int?          // image intrinsic size (aspect-ratio placeholder)
    var height: Int?
    var listStyle: ListStyle?
}
enum BlockType: String, Codable { case paragraph, heading, listItem, blockquote, preformatted, caption, image, divider }
```

**Caption rule:** `<figcaption>` becomes its own text-bearing `caption` block
placed after its image — NOT folded into the image block. Today's parser
already emits caption text as a paragraph in `plainText`; keeping captions
text-bearing preserves plainText compatibility, existing caption highlights,
and TTS reading them. `caption` renders in smaller secondary type beneath the
image.

```swift
enum ListStyle: String, Codable { case ordered, unordered }
```

(Video/transcript fields from the architecture doc are deferred to Phase 2b —
the JSON schema is versioned via `blocksVersion`, so adding fields later is safe.)

`Article` gains `blocksJSON: Data?` and `blocksVersion: Int = 0` (CloudKit-safe:
optional / inline default). Canonical rule: **`plainText` = text-bearing blocks
joined `"\n\n"`** — byte-identical to today's parser output, so existing
highlight offsets, TTS, and Obsidian export are unaffected.

`ArticleBlocks` helpers (same file): `decode(from:)`, `derivePlainText(_:)`,
and `textBlockBaseOffsets(_:)` → UTF-16 offset of each text block's start in
the derived `plainText` (block-local selection → global offset = base + local).

## Parser (Phase 1a)

Extend the existing JS block walk in `ArticleParser` to emit a typed block
array (same traversal; now tagging type, heading level, list style, and
emitting `<img>`/`<figure>` (src/alt/width/height; `<figcaption>` → a separate
`caption` block after the image) and `<hr>` → divider). Relative `src` resolved against
the article URL. Swift maps the JS dictionaries into `[ArticleBlock]`
(`ArticleParser.blocks(fromJS:)`, pure function, unit-tested with fixture
dictionaries — no WKWebView needed). `Parsed` carries `blocks`;
`PendingSaveIngest` stores `blocksJSON`. `plainText` is derived from the blocks
in Swift and must equal the old JS `join("\n\n")` output for text-only content
(pinned by test).

## Highlight anchoring upgrades (research amendments)

1. `Highlight` gains optional `prefixContext`/`suffixContext` (~32 UTF-16 units
   around the quote, captured at creation). CloudKit-safe optionals; old rows
   unaffected.
2. `HighlightAnchor.locate` cascade becomes: exact offsets → quote+context →
   quote alone (nearest match to the stale offset when multiple) → whitespace-
   collapsed quote. Never multiple-match into the wrong occurrence when a
   position hint exists.
3. Unicode-normalization pin test: NFC vs decomposed and smart-quote variants
   of the same text still re-anchor (documents the current behavior; fuzzy
   edit-distance matching remains Phase 3).

## Re-extract

`•••` overflow gains **Re-extract** (visible when `article.url != nil`):
re-runs `ArticleParser`, updates `plainText`/`extractedHTML`/`blocksJSON`/
`blocksVersion`, saves. Highlights re-locate via the anchor cascade on next
render (offsets refresh lazily as today). This is how pre-blocks articles gain
images.

## Block reader (Phase 2)

- `BlockReaderView`: `ScrollView` + `LazyVStack(spacing: settings.readerParagraphSpacing)`,
  horizontal insets from `ReaderWidth`, background from resolved theme.
- `TextBlockView`: one **non-scrolling `UITextView`** per text block
  (UIViewRepresentable), self-sizing, styled per type (heading sizes by level,
  blockquote indent + tint bar, listItem bullet/number prefix, preformatted
  monospace). Reuses the same font/theme/spacing settings and the composited
  highlight painting. Selection inside a block triggers the same instant-
  highlight edit menu; offsets map via the block's base offset. Cross-block
  selection is out of scope (Phase 4); the TextKit fallback still offers it.
- `ImageBlockView`: aspect-ratio reserved from width/height (no layout jumps),
  async load through new `ArticleImageCache` (URLSession + URLCache disk,
  NSCache decoded, downsample to container width), caption below, alt text for
  accessibility. Failure → compact broken-image placeholder.
- `DividerBlockView`: hairline.
- TTS: spoken paragraph index → nth text block → tinted background + scroll-to
  via `scrollPosition`. Scroll progress via `onScrollGeometryChange` feeding
  the existing `onScrollProgress` (read-tracking parity).

## Renderer selection & safety

`article.blocks != nil && settings.useBlockReader` → `BlockReaderView`; else
existing `HighlightableTextView` path (untouched, permanent fallback until
Phase 4). `useBlockReader: Bool = true` on `AppSettings` (local store), exposed
as a Settings → Reader toggle ("Block reader (beta)").

## Testing

Unit: block decode/derivation/base offsets; parser JS-dict mapping incl. image
attrs and relative URL resolution; plainText equality pin; anchor cascade
(context beats bare quote; nearest-match disambiguation; normalization pin);
Highlight field defaults. Sim: save/re-extract a real article (Wikipedia
fixture has images) → images render; highlight create/edit in block reader;
TTS tint + follow; flag-off falls back to TextKit; typography settings apply.

## Decisions log

| Decision | Choice |
|----------|--------|
| Scroll container | ScrollView + LazyVStack (UICollectionView escape hatch) |
| Text blocks | Non-scrolling UITextView per block; per-block selection only |
| Renderer flip | Flag `useBlockReader` default ON; TextKit path kept intact |
| Old articles | Re-extract action in ••• overflow |
| Image pipeline | ArticleImageCache: URLCache disk + NSCache decoded + downsample |
| Video/tables | Deferred (Phase 2b/3) |
| Anchor v2 | Context capture + smarter cascade now; diff-match-patch later |
