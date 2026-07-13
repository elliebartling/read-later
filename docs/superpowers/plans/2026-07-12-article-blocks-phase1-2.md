# Article Blocks Phase 1a + 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. One task per subagent (Opus), independent review after each. Steps use checkbox syntax.

**Goal:** Typed article blocks stored on `Article`, plus a native block reader (text/heading/list/quote/pre/caption/image/divider) with per-block instant highlighting, TTS tint/follow, scroll-progress parity, a `useBlockReader` flag with the TextKit path as fallback, Re-extract for old articles, and the research-derived anchoring upgrades.

**Read first:** `docs/superpowers/specs/2026-07-12-article-blocks-phase1-2-design.md` (binding decisions incl. the caption rule) and `docs/superpowers/specs/2026-07-11-article-blocks-plan.md` (architecture). AGENTS.md rules apply (iOS 26 floor, no gates needed; CloudKit-safe model fields; XCTest).

**Environment:** worktree `.claude/worktrees/article-blocks`, branch `claude/article-blocks` (stacked on `claude/ios26-floor`). Build/test via XcodeBuildMCP `build_sim`/`test_sim` (defaults already point here — never change session defaults). Baseline: 61/61 tests green.

**Plan style note:** Tasks 1–4 (model/parser/anchoring) specify exact code. Tasks 5–7 (UI) specify binding contracts + skeletons; the implementer designs internals following existing patterns (`HighlightableTextView` for representables, `TypographyControls` for settings UI). TDD where a unit seam exists; UI tasks verify by build + existing suite + the controller's end-to-end sim pass.

---

## Task 1: `ArticleBlock` model, derivation, base offsets, `Article` fields

**Files:** Create `Shared/Models/ArticleBlock.swift` · Modify `Shared/Models/Article.swift` · Test append `ReadLaterTests/ArticleBlockTests.swift` (new file)

- [ ] Tests first (new file `ReadLaterTests/ArticleBlockTests.swift`):

```swift
import XCTest
@testable import ReadLater

final class ArticleBlockTests: XCTestCase {
    private func block(_ type: BlockType, _ text: String? = nil) -> ArticleBlock {
        ArticleBlock(type: type, text: text)
    }

    func testDerivePlainTextJoinsTextBearingBlocksOnly() {
        let blocks: [ArticleBlock] = [
            block(.heading, "Title"),
            block(.paragraph, "One"),
            ArticleBlock(type: .image, src: URL(string: "https://x/img.jpg")),
            block(.caption, "A caption"),
            block(.divider),
            block(.paragraph, "Two"),
        ]
        XCTAssertEqual(ArticleBlocks.derivePlainText(blocks), "Title\n\nOne\n\nA caption\n\nTwo")
    }

    func testBaseOffsetsAreUTF16AndSkipNonText() {
        let blocks: [ArticleBlock] = [
            block(.paragraph, "Hé"),                 // "Hé" = 2 UTF-16 units
            ArticleBlock(type: .image, src: nil),
            block(.paragraph, "🙂ok"),               // emoji = 2 units
            block(.paragraph, "end"),
        ]
        let offsets = ArticleBlocks.textBlockBaseOffsets(blocks)
        // plainText = "Hé\n\n🙂ok\n\nend"
        XCTAssertEqual(offsets, [0, 4, 10])           // 2+2, then 4+4+2
    }

    func testCodableRoundTripAndUnknownTypeFails() throws {
        let original: [ArticleBlock] = [
            ArticleBlock(type: .heading, text: "H", level: 2),
            ArticleBlock(type: .listItem, text: "li", listStyle: .ordered),
            ArticleBlock(type: .image, src: URL(string: "https://a/b.png"), alt: "alt", width: 640, height: 480),
        ]
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([ArticleBlock].self, from: data), original)
    }

    func testArticleBlocksAccessorRoundTrip() throws {
        let article = Article(url: URL(string: "https://x")!, title: "t")
        XCTAssertNil(article.blocks)
        let blocks = [ArticleBlock(type: .paragraph, text: "p")]
        try article.setBlocks(blocks)
        XCTAssertEqual(article.blocks, blocks)
        XCTAssertEqual(article.blocksVersion, 1)
    }
}
```

(Adapt the `Article` initializer call to the real signature — read `Shared/Models/Article.swift` first; keep the test minimal.)

- [ ] Run `test_sim` → expect compile failure. Then implement `Shared/Models/ArticleBlock.swift`:

```swift
import Foundation

/// Typed reader blocks parsed from Readability HTML. `blocksJSON` on Article
/// stores `[ArticleBlock]` encoded as JSON (schema versioned by blocksVersion).
struct ArticleBlock: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: BlockType
    var text: String? = nil
    var level: Int? = nil
    var src: URL? = nil
    var alt: String? = nil
    var width: Int? = nil
    var height: Int? = nil
    var listStyle: ListStyle? = nil
}

enum BlockType: String, Codable {
    case paragraph, heading, listItem, blockquote, preformatted, caption
    case image, divider

    /// Whether this block's text participates in `plainText` (the highlight
    /// offset space) and TTS.
    var isTextBearing: Bool {
        switch self {
        case .paragraph, .heading, .listItem, .blockquote, .preformatted, .caption:
            return true
        case .image, .divider:
            return false
        }
    }
}

enum ListStyle: String, Codable { case ordered, unordered }

enum ArticleBlocks {
    static let currentVersion = 1

    /// Canonical rule: plainText = text-bearing blocks joined "\n\n".
    /// MUST stay byte-compatible with the parser's legacy join.
    static func derivePlainText(_ blocks: [ArticleBlock]) -> String {
        blocks.compactMap { $0.type.isTextBearing ? $0.text : nil }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// UTF-16 offset of each text-bearing block's start within derivePlainText.
    /// Block-local selection → global offset = base + local (both UTF-16).
    static func textBlockBaseOffsets(_ blocks: [ArticleBlock]) -> [Int] {
        var offsets: [Int] = []
        var cursor = 0
        for b in blocks where b.type.isTextBearing {
            guard let t = b.text, !t.isEmpty else { continue }
            offsets.append(cursor)
            cursor += t.utf16.count + 2 // "\n\n"
        }
        return offsets
    }

    static func decode(_ data: Data) -> [ArticleBlock]? {
        try? JSONDecoder().decode([ArticleBlock].self, from: data)
    }
}
```

- [ ] `Article.swift`: add CloudKit-safe stored fields + accessor (follow the existing field style):

```swift
    /// JSON-encoded [ArticleBlock]; nil until the article is (re)parsed by a
    /// blocks-aware parser. CloudKit-safe optional blob.
    var blocksJSON: Data?
    /// ArticleBlocks.currentVersion at encode time; 0 = no blocks.
    var blocksVersion: Int = 0
```

```swift
    var blocks: [ArticleBlock]? {
        guard let blocksJSON else { return nil }
        return ArticleBlocks.decode(blocksJSON)
    }

    func setBlocks(_ blocks: [ArticleBlock]) throws {
        blocksJSON = try JSONEncoder().encode(blocks)
        blocksVersion = ArticleBlocks.currentVersion
    }
```

- [ ] `test_sim` → all green (61 + 4 new). Commit: `Add ArticleBlock model, plainText derivation, and Article storage`.

---

## Task 2: Parser emits typed blocks; ingest stores them

**Files:** Modify `ReadLater/Services/ArticleParser.swift`, `ReadLater/Services/PendingSaveIngest.swift` · Test append `ReadLaterTests/ArticleBlockTests.swift`

**Contract:**
1. The JS walk (see the existing `blockText` IIFE) is extended to ALSO build `blocks`: an array of `{type, text?, level?, src?, alt?, width?, height?, listStyle?}` dictionaries, in document order, alongside the existing joined text. Mapping rules:
   - `H1`–`H6` → `heading` with `level` 1–6; `LI` → `listItem` with `listStyle` from the nearest `OL`/`UL` ancestor; `BLOCKQUOTE` leaf → `blockquote`; `PRE` → `preformatted` (preserve internal whitespace exactly as the legacy walk does); `FIGCAPTION` → `caption`; other leaf text blocks → `paragraph`.
   - `IMG` (also when nested in `FIGURE`/`PICTURE`) → `image` with `src` resolved absolute (`new URL(src, document.baseURI)`), `alt`, and `width`/`height` from attributes or `naturalWidth/Height` when present; skip images with no resolvable src, data: URIs, and tracking pixels (width or height attribute ≤ 2). A `FIGURE`'s `FIGCAPTION` emits a `caption` block immediately AFTER its `image`.
   - `HR` → `divider`. Skip empty text blocks (same emptiness rule as legacy).
2. JS returns `blocks` in the result dictionary; **the legacy `text` join stays** and `plainText` selection logic in Swift is unchanged for the fallback path, but when blocks parse successfully, `Parsed.plainText` MUST come from `ArticleBlocks.derivePlainText(blocks)` and a debug assertion compares it against the JS `text` for drift detection (log, don't crash, on mismatch — image-bearing pages can legitimately differ only if the legacy walk missed/kept different nodes; investigate any mismatch found in testing).
3. Swift: `static func blocks(fromJS: [[String: Any]], baseURL: URL) -> [ArticleBlock]` — a pure function mapping/validating the dictionaries (unknown `type` strings are DROPPED with a log, never fatal). `Parsed` gains `blocks: [ArticleBlock]`. `PendingSaveIngest` stores them via `article.setBlocks(_:)` alongside the existing field writes.
4. Tests (no WKWebView): feed `blocks(fromJS:baseURL:)` fixture dictionaries covering every type, relative URL resolution, tracking-pixel skip, unknown-type drop; pin `derivePlainText(mapped) == legacy join` for a text-only fixture.

- [ ] Tests first → red → implement → `test_sim` green. Commit: `Parse typed article blocks and store blocksJSON on save`.

---

## Task 3: Highlight anchor v2 — context capture + smarter cascade

**Files:** Modify `Shared/Models/Highlight.swift`, `ReadLater/Services/Highlighting/HighlightAnchor.swift`, `ReadLater/Features/Reader/ReaderView.swift` (capture on create) · Test append `ReadLaterTests/HighlightAnchorTests.swift`

**Contract:**
1. `Highlight` gains `var prefixContext: String? = nil`, `var suffixContext: String? = nil` (CloudKit-safe). Captured at creation (in `ReaderView.createHighlight`): up to 32 UTF-16 units before/after the quoted range in `plainText` (clamped at bounds; don't split surrogate pairs — slice via `NSString substring` on validated ranges or round outward to Character boundaries).
2. `HighlightAnchor.locate` cascade (extend the existing signature with optional `prefixContext:/suffixContext:` params defaulting nil, keeping all current call sites compiling):
   1. exact offsets whose text matches `quotedText` (existing),
   2. **quote+context**: occurrences of `quotedText` whose surrounding text matches prefix/suffix (when provided) — unique match wins,
   3. **quote alone, nearest to stale offset**: among all occurrences, pick the one whose start is closest to the stored `startOffset` (today's behavior returns the FIRST — fix that),
   4. whitespace-collapsed fallback (existing).
3. Callers pass the new fields where a `Highlight` is in hand (`HighlightableTextView.render`, tap hit-testing, etc. — grep `HighlightAnchor.locate`).
4. New tests: context disambiguates a quote occurring 3×; nearest-match beats first-match when no context; NFC vs decomposed-é and curly-vs-straight-quote pin test documenting current behavior (mark expectations honestly — if decomposed fails today, assert the *documented* outcome with a comment pointing at Phase 3 fuzzy matching); existing tests stay green (default params).

- [ ] TDD; `test_sim` green. Commit: `Capture highlight context and disambiguate re-anchoring`.

---

## Task 4: Re-extract action

**Files:** Modify `ReadLater/Features/Reader/ReaderView.swift`, `ReadLater/Features/Reader/AudioPlayerBar.swift` (IdlePlayerBar menu), plus whatever service plumbing the existing parse path needs (read `PendingSaveIngest`/`ArticleParser` first and REUSE the existing parse entry point — do not build a second parser pipeline).

**Contract:** `•••` overflow gains "Re-extract" (`arrow.clockwise` icon) above "Open Original", enabled when `article.url != nil`. Tapping: async re-parse of the URL via the existing `ArticleParser` path → on success update `title?` (NO — keep the user-visible title untouched), `plainText`, `extractedHTML`, `blocksJSON`/`blocksVersion`, `estimatedReadingMinutes`, save context. Progress: menu item disabled while running; failure → reuse the existing alert pattern (`tts.lastError`-style local `@State` alert, "Couldn't re-extract"). Highlights are NOT touched — they re-anchor lazily via the Task-3 cascade on next render. No unit tests (network+WKWebView path); verified in the controller's sim pass. Build + existing tests must stay green.

- [ ] Implement → `build_sim` + `test_sim` green. Commit: `Add Re-extract action to refresh an article's blocks`.

---

## Task 5: `ArticleImageCache` + `ImageBlockView` + `DividerBlockView`

**Files:** Create `ReadLater/Services/ArticleImageCache.swift`, `ReadLater/Features/Reader/Blocks/ImageBlockView.swift`, `ReadLater/Features/Reader/Blocks/DividerBlockView.swift` · Test append `ReadLaterTests/ArticleBlockTests.swift` (cache key/downsample math only)

**Contract:**
- `ArticleImageCache` (final class, singleton `shared`): `func image(for url: URL, targetWidth: CGFloat) async -> UIImage?`. URLSession with a dedicated `URLCache` (50 MB disk, App Group NOT needed — main app only); decoded-image `NSCache` keyed `"\(url.absoluteString)#\(Int(targetWidth))"`; downsample via `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceThumbnailMaxPixelSize` = targetWidth × screen scale) — never decode full-size into memory. Coalesce concurrent requests for the same key (task dictionary). Unit-test the cache key + max-pixel-size math via small pure helpers.
- `ImageBlockView` (SwiftUI): takes `block: ArticleBlock`, `containerWidth: CGFloat`, theme. Reserves aspect ratio from `width`/`height` when both exist (placeholder box, no layout jump; cap displayed height at 1.4 × container width for absurd panoramas — `scaledToFit` within), async-loads via the cache, fade-in on load, `accessibilityLabel(block.alt ?? "Image")`. Failure → compact rounded rect with `photo` SF symbol at 40 pt height. No caption inside (captions are separate blocks per the spec).
- `DividerBlockView`: theme-tinted hairline, centered, ~33% width.

- [ ] Implement (tests for the pure helpers first) → `test_sim` green. Commit: `Add article image cache and image/divider block views`.

---

## Task 6: `TextBlockView` — selectable text blocks with instant highlighting

**Files:** Create `ReadLater/Features/Reader/Blocks/TextBlockView.swift` (UIViewRepresentable + coordinator) · Test append: only if a pure seam emerges (offset mapping helper) — otherwise none.

**Contract (the heart of the feature — study `HighlightableTextView` first and mirror its patterns):**
- Represents ONE text-bearing block: inputs `block`, `baseOffset: Int`, full `plainText` (for context capture), `highlights: [Highlight]` (pre-filtered by the parent to those intersecting this block), `currentSpokenBlock: Bool`, resolved `theme`, font settings (size/family/lineSpacing), `defaultColor`, and the SAME callback set as `HighlightableTextView` (create/update/recolor/delete/note/tap-highlight/tap) — callbacks speak GLOBAL plainText offsets; the view converts via `baseOffset` both directions.
- Non-scrolling, non-editable, selectable `UITextView`; `isScrollEnabled = false` + `setContentCompressionResistancePriority(.required, for: .vertical)` so SwiftUI self-sizes it; zero `textContainerInset` (the stack owns margins).
- Per-type presentation: heading → font scaled by level (h1 ≈ ×1.6 semibold … h4+ ≈ ×1.15); blockquote → leading 4 pt tint bar + indent (secondary color); listItem → "• " or "n. " PREFIX RENDERED but excluded from offset math (prefix length subtracted when mapping selection→global and added when painting highlight ranges — this is the trickiest part; a pure `TextBlockOffsetMap` helper with unit tests is REQUIRED if you implement prefixes; alternatively render the marker in a separate leading label view and keep the text storage prefix-free — the label approach is RECOMMENDED and avoids mapping entirely); preformatted → monospace, horizontal scroll disabled, wrap; caption → footnote size, secondary color, centered.
- Instant highlight: same `editMenuForTextIn` trigger as `HighlightableTextView`, same menu (Color/Add Note/Remove + system), same session semantics within the block; created intents carry global offsets and context capture happens at the ReaderView layer (Task 3).
- Painting: composited `uiColor(darkBackground:)` backgrounds for the block's highlight ranges (global→local), spoken tint when `currentSpokenBlock`.

- [ ] Implement → `build_sim` green, suite green, unit tests for any offset-map helper. Commit: `Add selectable text block view with per-block instant highlighting`.

---

## Task 7: `BlockReaderView` + ReaderView integration + flag

**Files:** Create `ReadLater/Features/Reader/Blocks/BlockReaderView.swift` · Modify `ReadLater/Features/Reader/ReaderView.swift`, `Shared/Models/AppSettings.swift` (flag), `ReadLater/Features/Settings/SettingsView.swift` (toggle)

**Contract:**
- `AppSettings.useBlockReader: Bool = true` (local store; plain stored property). Settings → Reader section gains `Toggle("Block reader (beta)", isOn: $settings.useBlockReader)`.
- `BlockReaderView`: `ScrollView` + `LazyVStack(alignment: .leading, spacing: CGFloat(settings.readerParagraphSpacing))`, horizontal padding `settings.readerWidth.horizontalInset`, top/bottom insets matching the TextKit reader (24/40). Iterates `blocks`, dispatching to `TextBlockView`/`ImageBlockView`/`DividerBlockView`; precomputes `textBlockBaseOffsets` once per blocks change and pre-filters highlights per block (a highlight intersects a block if its located range overlaps `[base, base+len)` — locate ONCE per highlight against plainText, not per block).
- TTS: map `tts.currentParagraph` → nth text-bearing block; that block gets `currentSpokenBlock: true` and the view scrolls to keep it visible (`scrollPosition(id:)` binding, respecting user drag exactly like the TextKit path: don't fight active dragging).
- Scroll progress: `onScrollGeometryChange` → fraction = (offset + viewport)/contentHeight clamped 0…1 → existing `handleScrollProgress` (read-tracking keeps working).
- Tap on empty space toggles chrome (same as TextKit path's onTap).
- `ReaderView`: renderer selection — `if let blocks = article.blocks, !blocks.isEmpty, settings.useBlockReader { BlockReaderView(...) } else { HighlightableTextView(...) }` — the TextKit call site stays byte-identical. All highlight callbacks shared between both paths.
- `renderSignature`-style invalidation isn't needed (SwiftUI diffing per block), but blocks decode must be cached (`@State` keyed on `article.blocksVersion`/id, NOT decoded per body evaluation).

- [ ] Implement → `build_sim` + `test_sim` green. Commit: `Render block-based articles with the native block reader behind a flag`.

---

## Controller verification (after Task 7, not a subagent)

Sim pass: Book of Llandaff (Wikipedia, has images) → Re-extract → images + captions render in order; caption styled small; create/edit/recolor/delete a highlight inside a paragraph block; highlight an emoji-adjacent range; TTS: play → spoken block tints and follows; scroll to bottom → article marked read; toggle `useBlockReader` OFF → TextKit reader returns; typography sheet changes (theme/font/size/spacing/width) apply live in block reader; Re-extract failure path (airplane-mode) shows alert. Screenshot set for the PR.

## Self-review notes

- plainText compatibility is load-bearing everywhere: Task 1 derivation, Task 2 parity assertion + pin test, caption rule per spec.
- Offset spaces: only Task 6 touches local↔global mapping; the label-not-prefix recommendation eliminates the hardest bug class.
- All new model fields CloudKit-safe (optional or default). `useBlockReader` lives in the LOCAL store (AppSettings) — no CloudKit concern.
- TextKit path untouched except the ReaderView branch — the fallback stays provably intact (existing tests unchanged).
