# Reader Typography Settings — Design

**Date:** 2026-07-11  
**Status:** Approved for implementation planning  
**Approach:** Expand the existing `AppSettings` + `TypographyControls` + `HighlightableTextView` stack (no WebKit rewrite).

## Problem

Reader typography today is thin: theme (4 options), font size stepper (14–28), and five system fonts. Line height, paragraph spacing, and text width are hardcoded. Theme colors and flat-alpha highlight pastels do not scale well to additional paper colors.

## Goals

- Richer, accessible reading preferences without breaking UTF-16 highlight anchoring on `UITextView`
- Theme presets (not freeform colors) so ink, paper, and highlights stay contrast-safe
- Bundled open fonts for beautiful and accessible reading
- Sliders for size and spacing; named presets for column width
- Full controls in the in-reader Typography sheet; Settings stays light

## Non-goals (this pass)

- Live preview inside the Typography sheet (explicit **v2** follow-up)
- Per-article typography overrides
- Letter-spacing / word-spacing controls
- Dynamic Type coupling (keep absolute point sizes)
- True `CGBlendMode` custom highlight drawing
- Syncing reading prefs via CloudKit (remain on local-only `AppSettings`)

---

## Data model

Extend local-only [`AppSettings`](Shared/Models/AppSettings.swift) (single seeded row). All new attributes use inline defaults.

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `readerThemeRaw` | String | `"system"` | Existing; expand enum cases |
| `readerFontRaw` | String | `"Serif"` | Existing; expand enum cases |
| `readerFontSize` | Double | `18` | Existing; UI range becomes 12…32 |
| `readerLineSpacing` | Double | `6` | `NSParagraphStyle.lineSpacing` |
| `readerParagraphSpacing` | Double | `12` | `NSParagraphStyle.paragraphSpacing` |
| `readerWidthRaw` | String | `"medium"` | `ReaderWidth` raw value |

Unknown raw values fall back safely (same pattern as `readerTheme` today).

### `ReaderTheme`

Keep: `light`, `dark`, `sepia`, `system`.

Add:

| Case | Background (approx.) | Ink (approx.) |
|------|----------------------|---------------|
| `darkGray` | `#3A3A3C` (slightly lighter charcoal) | near-white |
| `mediumGray` | `#D1D1D6` (lighter mid gray) | near-black |
| `slate` | `#1E293B` | cool light |
| `paper` | `#F5F0E8` | soft brown-black |
| `forest` | `#1A2E1C` | light green-white |

Move `foreground` / `background` UIColor (and SwiftUI) helpers next to the enum so Settings and the reader share one source (today they live on an extension in `HighlightableTextView`).

### `ReaderWidth`

New enum: `narrow`, `medium`, `wide`, `full`.

Horizontal text-container insets (starting points; tune on device):

| Width | L/R inset |
|-------|-----------|
| Narrow | ~48pt (on wide iPad, also prefer a max content measure ~560pt via larger insets) |
| Medium | ~32pt |
| Wide | ~20pt (current feel) |
| Full | ~12pt |

Vertical insets stay ~24 top / ~40 bottom.

### `ReaderFont`

Expand [`ReaderFont`](ReadLater/UI/ReaderFont.swift) with:

**System (no download):** Serif (New York), Sans Serif (SF), Charter, Georgia, Palatino, Iowan.

**Bundled OFL (Regular + Italic where practical; prefer variable fonts when they reduce size):**

| Group | Faces |
|-------|-------|
| Reading | Literata, Source Serif 4, Merriweather, Charter, Serif, Georgia, Palatino, Iowan |
| Accessibility | Atkinson Hyperlegible Next, Lexend, OpenDyslexic |
| Sans | Geist, Inter, Sans Serif |

Each case exposes `group` for picker sections. `uiFont(size:)` resolves PostScript names for bundled faces and falls back to system serif/sans if registration fails.

Default remains Serif.

---

## Bundled fonts

- Path: e.g. `ReadLater/Resources/Fonts/<Family>/` including each family’s `OFL.txt` (or equivalent license file required by OFL condition 2)
- Register font files via `UIAppFonts` in the app Info.plist template / XcodeGen `project.yml` resources
- Ship only weights needed for body reading (Regular + Italic; optional Medium if a family’s Regular is too light)
- Do not add font sources to the test target (same Shared-sources rule: no duplicate types)

---

## UI

### Typography sheet ([`TypographyControls`](ReadLater/Features/Reader/TypographyControls.swift))

Primary home for all reading prefs. Sections:

1. **Theme** — wrapping chip/grid of paper swatches (9 themes; not segmented)
2. **Font** — grouped list (Reading / Accessibility / Sans) with live face preview per row
3. **Size** — slider 12…32, step 1
4. **Line spacing** — slider ~0…16, default 6
5. **Paragraph spacing** — slider ~0…28, default 12
6. **Width** — Narrow / Medium / Wide / Full chips or segmented control

Bindings write through `@Bindable AppSettings`. No in-sheet live body preview in this pass (reader updates behind the sheet). **v2:** add a short sample paragraph that reflects current settings.

### Settings tab

Keep a light Reader section: Theme + Size slider only. Font family, spacing, and width remain reader-sheet-only.

---

## Render path

Keep [`HighlightableTextView`](ReadLater/Features/Reader/HighlightableTextView.swift) as the single attributed-string `UITextView` path.

[`ReaderView`](ReadLater/Features/Reader/ReaderView.swift) passes theme, font, size, line spacing, paragraph spacing, and width.

Apply:

- Font via `ReaderFont.uiFont(size:)`
- Paragraph style from settings (replace hardcoded `lineSpacing = 6`, `paragraphSpacing = 12`)
- `textContainerInset` from `ReaderWidth`
- Theme background on the reader chrome; text color from theme foreground

Extend `renderSignature()` to include spacing and width so slider/width changes re-render. Highlight offsets remain UTF-16; location logic unchanged.

### Theme-aware highlight compositing

Today: `h.color.uiColor.withAlphaComponent(0.55)` — flat and harsh on dark/colored papers.

Replace with `HighlightColor.uiColor(on: ReaderTheme)` returning an **opaque** color:

- **Light themes** (light, sepia, paper, mediumGray, system-in-light): multiply-like compositing of marker into page (matches approved light preview)
- **Dark themes** (dark, darkGray, slate, forest, system-in-dark): brighter screen-like mid-tone bands so highlighted text stays readable (matches approved dark v2 preview)

Spoken-range tint uses the same helper family so it does not clash. Highlight identity (`yellow` / `green` / `blue` / `pink`) is unchanged; only the resolved paint color becomes theme-dependent.

Chip swatches in edit UI may continue showing the identity pastel; reader paint uses the composited color.

---

## Testing

XCTest (not Swift Testing):

- Theme / width / font raw-value fallbacks
- Width → inset mapping
- Highlight compositing: light vs dark produce distinct, opaque colors; light path darker-than-marker-on-white style; dark path brighter than the rejected muddy v1
- `ReaderFont` unknown raw → Serif; missing bundled file → system fallback (where testable)

No UI snapshot requirement in this pass.

---

## File touch list (expected)

- `Shared/Models/AppSettings.swift` — new fields; expand `ReaderTheme`; add `ReaderWidth`
- `Shared/Models/HighlightColor.swift` — theme-aware color resolution
- `ReadLater/UI/ReaderFont.swift` — cases, groups, bundled resolution
- `ReadLater/Features/Reader/TypographyControls.swift` — full UI
- `ReadLater/Features/Reader/HighlightableTextView.swift` — apply spacing/width; composited highlights; move theme colors if needed
- `ReadLater/Features/Reader/ReaderView.swift` — pass new settings
- `ReadLater/Features/Settings/SettingsView.swift` — size slider; leave family/spacing/width out
- `project.yml` / Info.plist fonts registration + font resources
- `ReadLater/Resources/Fonts/**` + license files
- New/extended unit tests under `ReadLaterTests/`

---

## Follow-ups

1. Live sample preview in Typography sheet (v2)
2. Trim rarely used system faces if the picker feels crowded
3. Optional Settings copy pointing to in-reader Typography
4. True blend-mode drawing only if composited colors prove insufficient

---

## Decisions log

| Decision | Choice |
|----------|--------|
| Color model | Named theme presets (not freeform bg/fg) |
| New themes | Dark Gray, Medium Gray (lighter), Slate, Paper, Forest |
| Text width | Named presets (not continuous slider) |
| Size/spacing | Three independent sliders |
| Controls location | Reader sheet primary; Settings light |
| Font picker | Grouped sections + face preview |
| Fonts | All researched OFL set + existing system set |
| Architecture | Expand existing stack (Approach 1) |
| Highlights | Theme-aware composited opaque colors (not CG blend mode) |
| Sheet live preview | Deferred to v2 |
