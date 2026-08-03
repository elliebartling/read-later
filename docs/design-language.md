# Design language — the ReadLater constitution

**Status:** draft, pending Ellen's ratification · **Supersedes:** nothing · **Motivated by:** [design audit 2026-08](design-audit-2026-08.md)

Every UI agent on this app is briefed with this file. It resolves the audit's eight cross-cutting themes so nobody re-decides them. If a rule here requires judgment to comply with, that is a bug in the rule — report it rather than guessing.

---

## 1. North star

### Ellen's brief, verbatim (2026-08-02, final)

> Minimalist without feeling clinical. It should feel modern and glass-like, an aesthetic that treats the content like it is precious and sacred. Pops of playfulness are also high-utility — they draw attention when needed, in a way that feels inviting, rather than needy or performative. ReadLater feels like it was built by someone who loves reading, who wants focus and sanctuary and beauty for the words, but who doesn't think reading has to be overly literary, pretentious, or paper-y. The app should feel subtle and calm and focused and clean. Layered and glass-like, clear/frosted.
>
> It is NOT: clinical, harsh, sharp, intense, old, cliche, traditional, or "bookish".

### Operating rules derived from it

| # | Rule | Traced to |
|---|---|---|
| N1 | Chrome always yields to content. Nothing in the app may be visually heavier than the words on the page. | "content… precious and sacred" |
| N2 | Separation is achieved by layered surfaces, material and light. **Never by an outline or a stroke around a container or a control.** | "layered and glass-like", "no borders" (reference notes) |
| N3 | Every pop of colour or motion must be answering a question the reader is already asking (what's new? did that save? which one is selected?). Colour that answers nothing gets deleted. | "high-utility… inviting, rather than needy or performative" |
| N4 | No paper, parchment, sepia-as-identity, washi, page curls, book spines, drop caps, or serif chrome. Reader *content* faces are exempt (see §4). | "not… paper-y", "NOT… bookish" |
| N5 | No pure black and no pure white as a page ground. No fully saturated hue larger than a 44pt control. | "NOT… harsh, sharp, intense" |
| N6 | Prefer the current-generation Apple material over a hand-rolled equivalent. If SwiftUI ships it, use it. | "modern", "NOT… old, cliche, traditional" |
| N7 | Two schemes, one app. Every rule below is specified for light **and** dark, and a change that lands in one without the other is incomplete. | audit theme 3 (a light-only defect nobody caught) |

---

## 2. Palette

All values are sRGB hex, derived in OKLCH. Hue **72°** at chroma ≤ 0.006 is the neutral spine of both schemes: enough warmth that the greys read as charcoal rather than clinical slate (N5), far too little to read as cream or paper (N4). Craft's ground samples at `#222222` (OKLCH L 0.252, chroma 0.0); Ellen's ruling was **Craft's warm charcoal over GoodLinks' true black**, so we keep Craft's lightness and add the warmth its screenshots only imply.

### 2.1 Neutral ramp (both schemes)

Light mode is a **warm near-white, not a cream**. The guard: light neutrals are capped at chroma 0.004 — above 0.006 at these lightnesses it reads as parchment and violates N4. Contrast figures are against that scheme's `ground`.

| Token | Dark | Light | Use |
|---|---|---|---|
| `Surface.ground` | `#211F1C` | `#F8F6F5` | The page. Every tab, every full-screen surface. |
| `Surface.raised` | `#2C2A27` | `#FFFEFD` | Grouped list containers, cards, note bubbles, fields. |
| `Surface.elevated` | `#373532` | `#FFFFFF` | Sheets, popovers, selected rows, chip fills. |
| `Surface.control` | `#44423F` | `#EDEAE8` | Non-glass button fills, tracks, thumbnail placeholders. |
| `Surface.divider` | `#33312F` | `#E1DFDD` | The **only** legal 0.5pt line, inside a list container only (S3). |
| `Ink.primary` | `#F2F0ED` 14.5:1 | `#23201C` 15.1:1 | Titles, body, primary labels. |
| `Ink.secondary` | `#B3B0AD` 7.6:1 | `#5E5A55` 6.4:1 | Metadata, summaries, read-state titles. Body-safe on every surface (5.7:1 dark on `elevated`). |
| `Ink.tertiary` | `#9C9996` 5.8:1 | `#716C67` 4.8:1 | Light value is body-safe anywhere; the dark value drops to 4.3:1 on `elevated`, so on dark it is body-safe on `ground` only — icons and ≥17pt labels above that. |
| `Ink.quaternary` | `#6B6866` | `#9B9893` | Never text. Disabled glyphs only. |

**Light-mode elevation runs out of headroom above `raised`.** Beyond it, elevation is material and shadow, never more lightness (§3).

### 2.2 The accent system (resolves [audit theme 2](design-audit-2026-08.md#2-accent-colour-has-no-system--pink-appears-exactly-once-and-it-is-the-loudest-thing-in-the-app))

The audit found six colours doing accent duty and one — `Color.playerPink` `#FF2D55` at full saturation — being the loudest thing in the app on exactly one screen (exhibit in §3 below).

**Ruling: `Color.playerPink` is retired, not re-homed.** A fully saturated `#FF2D55` is disqualified by N5 ("NOT… harsh, sharp, intense") regardless of where it is placed. The token is deleted; the audio capsule becomes glass with an Iris transport (§5.3). Pink survives in exactly one place: `HighlightMarker.pink`, where the user chose it.

There are four colour tiers and they never borrow from each other.

**Tier 1 — brand accent. Exactly one hue: Iris.** A violet-indigo at OKLCH hue 293°: distinct from every highlight hue, from all three source hues, and from Apple's default blue (which reads as "unstyled", violating N6).

| | Dark | Light |
|---|---|---|
| `Accent.iris` (glyphs, text, selection, unread) | `#9D84EC` — 5.4:1 on ground | `#663CBC` — 6.6:1 on ground, white-on-it 7.2:1 |
| `Accent.irisFill` (tinted backgrounds, ≤10% of a screen) | `#393350` | `#EBE8FE` |

Iris appears on: the selected tab, unread indicators, selection checks, the TTS transport, active toggles, links, and the primary action in any sheet. Nowhere else. Budget: **one Iris-filled element per screen**, unlimited Iris glyphs/text.

**Tier 2 — semantics.** One meaning each. Never decorative.

| Role | Dark | Light |
|---|---|---|
| `Semantic.success` (sync complete, saved) | `#51C672` 7.6:1 | `#007E17` 4.9:1 |
| `Semantic.destructive` (delete, remove highlight) | `#FF716B` 6.1:1 | `#C20011` 5.9:1 |
| `Semantic.warning` (parse failed, stale feed) | `#E49900` 6.9:1 | `#9E4900` 5.7:1 |

**Tier 3 — highlight colours: a privileged tier, because they are the app's core taxonomy** ([theme 7](design-audit-2026-08.md#7-colour-is-the-apps-core-taxonomy-and-it-is-barely-rendered)). Split into two roles the current code conflates. **Paint** is what sits behind text — unchanged; `HighlightColor.uiColor(darkBackground:)` is protected work and nobody may replace its multiply-on-light / screen-on-dark composite with a plain alpha. **Marker** is the identity chip (swatches, picker circles, Highlights-tab indicator, notebook rail) — new, saturated, and where GoodLinks' brightness lives, because it never sits behind text.

| | Marker (both schemes) | Light paint | Dark paint |
|---|---|---|---|
| yellow | `#F9CC21` | `#FCF3BE` | `#7E7858` |
| green | `#43D066` | `#D6F4D6` | `#667966` |
| blue | `#00A5ED` | `#D0E6FC` | `#63717E` |
| pink | `#F6519A` | `#FCDAE8` | `#7E6972` |

Markers carry `Ink.primary` (dark value) glyphs, never white — white-on-yellow is 1.5:1.

**Tier 4 — source identity.** Feeds have three kinds and the app shows none of it. Chips take the source's recognised hue at *our* chip lightness, so the column reads as one family rather than a logo parade.

| | Dark | Light |
|---|---|---|
| `Source.youtube` | `#E8605B` | `#CF4040` |
| `Source.reddit` | `#DC7200` | `#C45500` |
| `Source.website` | `#3F93F7` | `#1779E1` |

Reddit is pulled to hue 58° rather than its brand 35° because at our lightness the brand value is indistinguishable from YouTube's. The glyph, not the hue, is the primary discriminator.

**Tier 0 — transient system state has no hue.** Reading position (TTS) and search matches must never look like a user's highlight. They render as a **luminance wash only** (`#312F2C` dark, `#E9E7E5` light) plus a 3pt `Accent.iris` leading rail. Iris is violet; every highlight is warm or azure; the two cannot be confused.

---

## 3. Surfaces & glass (resolves [theme 1](design-audit-2026-08.md#1-there-is-no-surfaceelevation-system-so-tabs-dont-feel-like-one-app) and [theme 3](design-audit-2026-08.md#3-reader-chrome-does-not-separate-itself-from-content--and-it-fails-asymmetrically-by-scheme))

Today Feeds is `.plain` on `systemBackground` and Highlights is grouped, so two sibling tabs are two different apps:

| Feeds (plain) | Highlights (grouped) |
|---|---|
| ![Feeds light](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/07-feeds-list-light.png) | ![Highlights light](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/26-highlights-populated-light.png) |

**There are exactly four elevations. No fifth.**

| Level | What it is | Fill | Corner | Shadow |
|---|---|---|---|---|
| **E0 — ground** | The page. One per screen. | `Surface.ground` | — | none |
| **E1 — container** | Grouped list container, card, field, note bubble. | `Surface.raised` | 16pt continuous | none in dark; `y2 blur8 α0.05` in light |
| **E2 — modal** | Sheets, popovers, menus. | `Surface.elevated` | system | system |
| **E3 — floating glass chrome** | Anything hovering over scrolling content: nav pills, tab bar, audio capsule, reader toolbars. | material, see S4 | full capsule or 22pt | `y4 blur16 α0.18` dark / `α0.10` light |

- **S1.** Every list is `.listStyle(.insetGrouped)` on `Surface.ground` with `.scrollContentBackground(.hidden)`. Delete every other `listStyle` in the app. One page surface, one container surface — that is the whole system.
- **S2. No strokes.** No `.border`, no `.overlay(RoundedRectangle().stroke())`, no `.background(...).cornerRadius()` faking an outline, on any container or control. Separation is E0→E1 value step plus 16pt of ground (N2).
- **S3. One exception, tightly scoped:** rows *inside* one E1 container may be separated by a 0.5pt `Surface.divider` inset to the text column. This is the only line in the app. It is not a border; it never surrounds anything.
- **S4. Floating chrome material floor.** Over long-form text: `.regularMaterial` in **both** schemes, plus the `Surface.chromeTint` overlay defined here and nowhere else: `#262421` at 0.35 alpha (dark), `#FBFAF8` at 0.45 alpha (light). `.ultraThinMaterial` and `.thinMaterial` are banned over the reader — they are the reason body text currently renders through the nav bar in light mode. Over short/static content (a settings header) `.thinMaterial` is fine.
- **S5. Chrome reserves its own space.** Every floating chrome element publishes `its height + 12pt` as a `safeAreaInset(edge:)` on the scroll view. Content never passes under chrome at rest — not the top bar, not the audio capsule, not the tab bar. This is [fix #1](design-audit-2026-08.md#if-we-fix-only-ten-things) stated as a rule.
- **S6. Revealing chrome must not move text.** The inset is reserved whether chrome is shown or hidden. The plain reader already does this with a frozen inset; the block reader must match.

| Light — the S4 defect | Dark — same bar, fine |
|---|---|
| ![Light chrome](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/20-reader-chrome-legibility-light.png) | ![Dark chrome](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/43-reader-chrome-dark.png) |

---

## 4. Typography

**Reader typography is finished work and is out of scope.** New York at 18pt / 6pt leading / 12pt paragraph spacing, the eight-theme ink+paper system, the eleven-face catalogue with bundled Atkinson Hyperlegible and Lexend — the audit graded all of it *good* and it stays. Codified so nobody "improves" it:

- **T1.** Reader body face, size, leading, paragraph spacing, measure and page colour come from the theme + typography settings. No UI agent hardcodes any of them.
- **T2.** The reader canvas may be darker than `Surface.ground`; it may never be lighter in dark mode, or darker in light mode. Entering the reader is a step *into* sanctuary.
- **T3.** Serif faces are legal **only** for reader body content. All chrome, all UI, all sheets: system sans (N4).

**UI type is the work.** One family (SF Pro), hierarchy by weight and size only.

| Role | Style | Weight | Colour |
|---|---|---|---|
| Screen title | `.largeTitle` | `.bold` | `Ink.primary` |
| Section header | `.subheadline` | `.semibold` | `Ink.secondary` |
| Row title | `.body` | `.semibold` (unread) / `.regular` (read) | `Ink.primary` / `Ink.secondary` |
| Row summary | `.subheadline` | `.regular` | `Ink.secondary`, `lineLimit(2)` |
| Metadata | `.caption` | `.regular` | `Ink.tertiary` |
| Button label | `.body` | `.semibold` | per §5 |
| Chip / badge | `.caption2` | `.semibold` | per §5 |

- **T4.** Every string is sentence case except proper nouns: "Add feed", "Import subscriptions", "Line spacing". No Title Case anywhere (the audit found both in one menu), no all-caps labels, no tracked eyebrows.
- **T5.** Any single-line label that can receive arbitrary content gets `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: false)`. The "Saved" badge currently wraps to "Save" / "d":

  ![Saved badge break](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/16-feedentries-savedbadge-break-light.png)
- **T6.** Dynamic Type is supported to `.accessibility3` on every surface. Rows grow; they never truncate the title to preserve metadata.

---

## 5. Component contracts

### 5.1 The list row — one grammar (resolves [theme 4](design-audit-2026-08.md#4-the-same-information-class-is-expressed-with-a-different-grammar-in-each-list))

Library and Feeds currently share nothing: two unread signals, two metadata grammars, two source formats, thumbnails in one and not the other.

![Library populated](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/35-library-populated-light.png)
![All Items](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/08-allitems-light.png)

**There is one row component, `ReadableRow`, with declared slots.** Library, All Items, per-feed lists and Search all use it.

```
[unread rail] [ title (2 lines max) ]                [thumbnail]
              [ summary (2 lines, optional) ]        [ 96×54 ]
              [ meta · meta · meta ]
```

- **R1. Unread signal is one thing: a 3pt `Accent.iris` leading rail**, full row height, inset 0. Not a dot, not a colour change, not both. Read rows drop the rail and shift the title to `Ink.secondary`.
- **R2. Metadata is a single `.caption` line, `Ink.tertiary`, fields joined by `" · "`.** No SF Symbols in the meta line, no bare spaces. Field order is fixed and identical everywhere: `source · relative date · duration/count`. A field that duplicates the screen's nav title is omitted (per-feed lists drop `source`).
- **R3. Source string has one format**, produced by one helper: `siteName` if present, else host with `www.` stripped. Never three formats in three adjacent rows.
- **R4. Thumbnails are trailing, 96×54, 8pt corner, and every row reserves the slot** when the list can contain thumbnails — an empty slot renders `Surface.control`, so rhythm never goes ragged. Library gets thumbnails.
- **R5. Row height is fixed per list at 3 lines minimum.** A row missing summary or metadata pads; it does not collapse.
- **R6. Every row is a real `NavigationLink`** with the system disclosure. No hidden links in a `ZStack`, no `Button`s masquerading as rows. Highlights rows link to the passage.
- **R7. Failure is visible in the list.** An article that failed to parse shows a `Semantic.warning` glyph in the meta line. You should never learn about a failure by opening it.

### 5.2 Sheets (resolves [theme 6](design-audit-2026-08.md#6-sheets-have-no-shared-contract))

Four dismissal verbs, three heights, three selection idioms today.

| Sheet role | Dismiss verb set | Detent |
|---|---|---|
| **Editor** — changes commit live (Typography, Highlight edit, Tags) | `Done` only, trailing | `.medium` so you can see what you are changing |
| **Form** — changes commit on confirm (Add URL, Add feed) | `Cancel` leading / `<Verb> object` trailing | `.height(220)`; one field never gets a full screen |
| **Informational** — nothing to commit (Import subscriptions, Settings) | `Done` trailing | `.large` |

- **SH1. Every sheet has a visible dismiss control.** Swipe is never the only exit. (Settings currently has no exit at all.)
- **SH2. One selection idiom app-wide:** a filled `Accent.iris` circle with a white checkmark, trailing. Not a ring here, a check-in-swatch there, blue text elsewhere.
- **SH3. Confirm verbs are verb + object**: "Add feed", "Save link". Never "OK", never a bare "Subscribe" when the sibling sheet says "Save".
- **SH4. Explanatory subtitles are never tinted.** If a row is a `Button`, its subtitle is explicitly `Ink.secondary` — the Import sheet paints its own explanation blue:

  ![Import](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/31-youtube-import-light.png)
- **SH5. An editor sheet shows the thing it edits.** The highlight sheet must render the quoted passage.

### 5.3 Floating chrome, pills and buttons

Seven button vocabularies today. **There are three.**

| Vocabulary | Shape | Use |
|---|---|---|
| **Glass circle** | 44pt circle, `.regularMaterial` + chromeTint, `Ink.primary` glyph | Every nav-bar and floating single action. Back, settings, add, mark-all-read, sidebar trigger. |
| **Glass capsule** | height 52, `.regularMaterial` + chromeTint, capsule | Multi-glyph clusters and the audio capsule. |
| **Prominent capsule** | `Accent.iris` fill, white label, `.body/.semibold` | The one primary action on a screen. Max one. |

- **C1.** Plain tinted text as a button is banned. "Export all articles" and "Save key" become prominent capsules or rows with disclosure.
- **C2. The audio capsule has one width.** It reserves its playing-state width at idle; it does not grow from 340pt to full-width when you press play. Transport glyphs are `Accent.iris`; the ribbon is `Accent.iris` at full brightness for played, `Ink.quaternary` for remaining.
- **C3. The capsule is state-aware.** On an article with no content it offers Retry and Share only — not Play.
- **C4.** Chrome over the reader obeys S4, S5, S6. No exceptions for "just this one bar".

### 5.4 Highlight rendering

- **H1.** Any place a highlight colour is shown, it is shown *in colour*, as a 20pt `HighlightMarker` circle. The text-list picker ("Yellow / Green / Blue / Pink") is deleted; the swatch row is the only picker component, used in the edit menu, the edit sheet and any future surface.

  | Delete this | Keep this |
  |---|---|
  | ![Colour menu](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/22-highlight-colormenu-light.png) | ![Edit sheet](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/23-highlight-editsheet-light.png) |
- **H2.** In the Highlights tab and the notebook view, the colour is a **4pt full-height leading rail** in the marker colour, not an 8pt dot. Quote leads; source metadata follows beneath at `.caption` / `Ink.tertiary`. Hierarchy is content-first.
- **H3.** Highlights group by article, one header per article.
- **H4.** Highlight paint applies instantly on selection. Never animated (§7).
- **H5.** Reading position and search matches use Tier 0 only (§2.2). A yellow band behind a paragraph means the user highlighted it. Nothing else may claim that signal.

### 5.5 Empty states

`Site Logins` is the template — centred, and it explains the mechanism that would fill the void rather than naming the void.

![Site Logins](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/30-sitelogins-empty-light.png)

- **E1.** `ContentUnavailableView` is always an `.overlay` on the scroll view, centred in the viewport. Never a list row, never boxed in a card. (Three placements exist today.)
- **E2.** Structure: `Ink.tertiary` SF Symbol, title, one sentence naming the mechanism, and — if the copy names an action — that action as a prominent capsule.
- **E3.** Failure states get `Semantic.warning`, empty states get no colour at all.

### 5.6 The bento grid

**Reserved for exactly one surface: the reader's typography/appearance picker.** Mixed-size tiles on `Surface.raised`, each a live self-illustrating preview (the theme tile renders real ink on real paper; the font tile renders its own face). It collapses today's four grouped sections, four headers and two slider treatments into one spatial panel, and it is the only place in the app where a grid replaces a list.

![Typography sheet today](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/13-typography-sheet-light.png)

- **B1.** No paper-swatch fans, no page curls, no textures on the tiles (N4). The preview *is* the decoration.
- **B2.** Numeric controls put their value trailing the control, never on their own row. One slider treatment: bare track, trailing value.
- **B3.** The sheet is `.medium` so the article stays visible while being tuned. Read Aloud lives in Settings only — the duplicate is removed here.

---

## 6. Playfulness budget

Playfulness is **attention direction with a personality**, and the budget is deliberately small: "inviting, rather than needy or performative" (N3). It is spent in four moments and no more.

1. **Source identity chips** (§2.2 Tier 4). Filled circular chips with a source glyph in Feeds and the sidebar. This is the GoodLinks icon-chip dialect, and it is high-utility: it is the only way to tell a subreddit from a channel at a glance.
2. **The unread rail** (R1). Iris, and it is the single most-repeated colour event in the app, so it stays a rail and never a badge.
3. **Save confirmation.** When a link lands from the share sheet, the new row enters with the spring in §7 and its rail flashes to `Semantic.success` for 600ms before settling to Iris. One event, self-cancelling.
4. **First-run import moments** (YouTube subscription import, feed add). A live count that ticks up as sources land. Numbers moving is the whole effect.

**The NOT list, straight from the brief:** no confetti, no badge counts that beg, no bounce, no mascot, no illustration style, no washi tape, no paper textures, no page curls, no drop caps, no serif chrome, no gradient text, no rainbow accent rings, no skeuomorphic anything, no sound. Nothing decorative that answers no question (N3).

---

## 7. Motion

"Smooth and beautiful… everything feels intentional" is a requirement, not a nice-to-have.

| Class | Curve | Use |
|---|---|---|
| **Micro** | `.easeOut(duration: 0.18)` | Tint changes, checkmarks, toggle states, glyph swaps. |
| **Standard** | `.spring(response: 0.34, dampingFraction: 0.88)` | Chrome reveal/hide, row insert/remove, capsule reshaping, sheet content. Damping 0.88 = settles without overshoot. |
| **Attention** | `.spring(response: 0.28, dampingFraction: 0.72)` | The four playful moments in §6 only. This is the only curve with any overshoot, and it is capped there. |
| **Navigation** | system default | Push, pop, sheet present. Never overridden. |

- **M1. Never animate:** reader body text layout, font-size or line-spacing changes (apply instantly — animating reflow makes text crawl), scroll position restore, highlight paint appearance, list content on first appear.
- **M2. Chrome reveal fades and scales from 0.96; it never slides content** (S6). No animation exceeds 0.4s; no bounce, no elastic, no curve outside the table above.
- **M3. Reduce Motion is not optional.** Every Standard and Attention animation degrades to a 0.15s crossfade. Springs are wrapped so this is one check, not one per call site.
- **M4.** Haptics pair with the Attention class only: `.success` on save, `.selection` on highlight-colour change. Nowhere else.

---

## 8. Phase-3 wave plan

Four waves, each independently mergeable and reviewable, ordered by visible gain per unit of risk. Wave 1 is a hard dependency for 2–4 (they all consume the tokens); 2, 3 and 4 are independent of each other and can run in parallel across sessions.

**Already filed elsewhere — excluded from every wave:** [#63](https://github.com/elliebartling/read-later/issues/63) content-fidelity batch (audit theme 8, fix #10) and [#64](https://github.com/elliebartling/read-later/issues/64) block-reader reading-position restore (theme 5, fix #8). Both are correctness bugs, not design work. [#57](https://github.com/elliebartling/read-later/issues/57) (sidebar experiment: decide after on-device trial) is Ellen's call and **gates Wave 4** — that IA decision is upstream of source identity landing anywhere.

### Wave 1 — Ground (tokens, surfaces, reader chrome)

*The app stops being a collage. Largest perceived-quality jump per line changed.*

| Item | Audit ref | Kind |
|---|---|---|
| Ship §2 as a token file; delete `Color.playerPink` | theme 2 | code |
| One list style app-wide; delete every ad-hoc `listStyle` | theme 1, fix #2 | code |
| Reader chrome to `.regularMaterial` + chromeTint, both schemes | theme 3, fix #1 | code |
| `safeAreaInset` for every floating chrome element (S5, S6) | theme 3 | code |
| Strip every stroke/border (S2), introduce the E0–E3 scale | theme 1 | code |

**Taste-check:** the exact ground values on Ellen's device in a dark room. Everything else is mechanical.

### Wave 2 — Grammar (one row, one meta line, one empty state)

*Four lists stop being four apps.*

| Item | Audit ref | Kind |
|---|---|---|
| `ReadableRow` with declared slots; adopt in Library, All Items, per-feed, Search | theme 4, fix #9 | code |
| One metadata grammar (R2) and one source-string helper (R3) | theme 4 | code |
| Thumbnail slot always reserved; Library gets thumbnails (R4) | Library | **taste-check** (R4 is the one row decision) |
| `lineLimit`/`fixedSize` sweep; fixes the "Save"/"d" wrap | fix #3 | code |
| Hanging indents + list-item spacing in the block reader | fix #4 | code |
| Inline-code treatment in the block reader | Block reader | code |
| Empty-state template (E1–E3) applied to Library, Feeds, Highlights, Tags | multiple | code |

### Wave 3 — Colour (the taxonomy finally renders)

*A highlighting app whose highlight colours barely appear.*

| Item | Audit ref | Kind |
|---|---|---|
| Marker/paint split; add `HighlightColor.marker` | theme 7 | code |
| Delete the text-only picker; one swatch component everywhere (H1) | theme 7, fix #5 | code |
| Spoken-paragraph tint → Tier 0 wash + Iris rail (H5) | theme 7, fix #6 | code |
| Highlights tab: rail, content-first hierarchy, group by article, tap through to passage (H2, H3, R6) | Highlights, fix #7 | code + **taste-check** on grouping header design |
| Iris rollout: tab bar, unread rails, selection checks, TTS transport | theme 2 | code |
| Semantic roles applied (success/destructive/warning) | theme 2 | code |

### Wave 4 — Chrome, identity and delight

*Gated on #57: everything below assumes the navigation question is settled.*

| Item | Audit ref | Kind |
|---|---|---|
| Sheet contract: verbs + detents + dismiss controls (SH1–SH5) | theme 6 | code |
| Button vocabulary 7 → 3 (§5.3) | button inventory | code |
| Audio capsule: fixed width, state-aware, Iris transport (C2, C3) | TTS | code |
| Source-kind identity chips in Feeds/sidebar (Tier 4) | Feeds, sidebar | **taste-check** + gated on #57 |
| Typography sheet → bento grid (§5.6) | Typography sheet | **taste-check** |
| Settings: dismiss control, one icon treatment, de-duplicate Reader/Read Aloud | Settings | code |
| Motion pass: §7 curve tokens, Reduce Motion wrapper, the four playful moments | §6, §7 | **taste-check** on the save-confirmation moment |

---

## Compliance

A UI change is compliant when: it uses only §2 tokens, sits at one of the four §3 elevations, adds no stroke, reserves inset for any floating chrome, uses `ReadableRow` if it is a row, uses a §7 curve if it animates, and looks correct in both schemes at `.accessibility3`. If a task seems to need a rule that is not here, the rule is missing — raise it rather than inventing one locally.
