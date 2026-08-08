# Design language — the ReadLater constitution

> **Errata (2026-08-03, wave 1):** two internal inconsistencies were resolved in code and now govern: (1) §7.2's nested-radius worked example did not follow its own formula — the FORMULA wins; (2) §7.3's capsule metrics (44pt height + 30pt play + 10pt padding) over-summed — the 44pt HEIGHT wins, padding derives (10 idle / 7 playing).
>
> **Amendments (2026-08-04, wave 5) — all four ratified by Ellen** on the built results of PRs #72 and #73, and marked inline where they land: **S1a** the sidebar is flat (one continuous ground, no per-section cards, one selection wash); **S7** never put a border on only one side of a rounded card; **BR2/BR3/§7.2** monograms and kind tiles are rounded squares at the favicon-tile radius, never circles; **§2.2** the system-state wash is paper-relative — the token is the ±16/255 luminance *step*, not the two literal colours.


**Status:** **ratified** by Ellen, 2026-08-03 · **Motivated by:** [design audit 2026-08](design-audit-2026-08.md)

Every UI agent on this app is briefed with this file. It resolves the audit's eight cross-cutting themes so nobody re-decides them. If a rule here requires judgment to comply with, that is a bug in the rule — report it rather than guessing.

**v2 changes:** the brand accent is **deferred** (§2.3–2.4) — v1 ships true neutrals with abstract accent plumbing. Four new sections: [Iconography](#5-iconography), [Third-party brand representation](#6-third-party-brand-representation), a real [typography POV](#4-typography), and [sizing standards](#7-sizing-controls-containers-spacing). The sidebar is the adopted default navigation.

**Ratification amendment:** SF Symbols are the **interim** icon standard, not the end state. A full third-party glyph pass is planned and explicitly sequenced last (§5.4, wave 6).

---

## 1. North star

### Ellen's brief, verbatim (2026-08-02, final)

> Minimalist without feeling clinical. It should feel modern and glass-like, an aesthetic that treats the content like it is precious and sacred. Pops of playfulness are also high-utility — they draw attention when needed, in a way that feels inviting, rather than needy or performative. ReadLater feels like it was built by someone who loves reading, who wants focus and sanctuary and beauty for the words, but who doesn't think reading has to be overly literary, pretentious, or paper-y. The app should feel subtle and calm and focused and clean. Layered and glass-like, clear/frosted.
>
> It is NOT: clinical, harsh, sharp, intense, old, cliche, traditional, or "bookish".

### Operating rules derived from it

| # | Rule | Traced to |
|---|---|---|
| N1 | Chrome always yields to content. Nothing may be visually heavier than the words on the page. | "content… precious and sacred" |
| N2 | Separation is layered surfaces, material and light. **Never an outline or stroke around a container or control.** | "layered and glass-like"; "no borders" (reference notes) |
| N3 | Every pop of colour or motion must answer a question the reader is already asking (what's new? did that save? which is selected?). Colour that answers nothing gets deleted. | "high-utility… inviting, rather than needy or performative" |
| N4 | No paper, parchment, sepia-as-identity, washi, page curls, book spines, drop caps, or serif chrome. Reader *content* faces are exempt (§4.1). | "not… paper-y", "NOT… bookish" |
| N5 | No pure black and no pure white as a page ground. No fully saturated hue larger than a 44pt control. | "NOT… harsh, sharp, intense" |
| N6 | Prefer the current-generation Apple material over a hand-rolled equivalent — but a system default is not automatically right where it reads as *unstyled* (§5). | "modern"; "NOT… old, cliche, traditional" |
| N7 | Two schemes, one app. Every rule is specified for light **and** dark; a change landing in one without the other is incomplete. | audit theme 3 (a light-only defect nobody caught) |

---

## 2. Palette

All values are sRGB hex, derived in OKLCH. Hue **72° at chroma ≤ 0.006** is the neutral spine of both schemes: enough warmth that the greys read as charcoal rather than clinical slate (N5), far too little to read as cream or paper (N4). Craft's ground samples at `#222222` (OKLCH L 0.252, chroma 0.0); Ellen's ruling was **Craft's warm charcoal over GoodLinks' true black**, so we keep Craft's lightness and add the warmth its screenshots only imply.

### 2.1 Neutral ramp (both schemes)

Light mode is a **warm near-white, not a cream**. The guard: light neutrals are capped at chroma 0.004 — above 0.006 at these lightnesses it reads as parchment and violates N4. Contrast figures are against that scheme's `ground`.

| Token | Dark | Light | Use |
|---|---|---|---|
| `Surface.ground` | `#211F1C` | `#F8F6F5` | The page. Every destination, every full-screen surface. |
| `Surface.raised` | `#2C2A27` | `#FFFEFD` | Grouped list containers, cards, note bubbles, fields. |
| `Surface.elevated` | `#373532` | `#FFFFFF` | Sheets, popovers, selected rows, chip fills. |
| `Surface.control` | `#44423F` | `#EDEAE8` | Non-glass button fills, tracks, thumbnail and favicon tiles. |
| `Surface.divider` | `#33312F` | `#E1DFDD` | The **only** legal 0.5pt line, inside a list container only (S3). |
| `Ink.primary` | `#F2F0ED` 14.5:1 | `#23201C` 15.1:1 | Titles, body, primary labels. |
| `Ink.secondary` | `#B3B0AD` 7.6:1 | `#5E5A55` 6.4:1 | Metadata, summaries, read-state titles. Body-safe on every surface (5.7:1 dark on `elevated`). |
| `Ink.tertiary` | `#9C9996` 5.8:1 | `#716C67` 4.8:1 | Light value is body-safe anywhere; dark drops to 4.3:1 on `elevated`, so on dark it is body-safe on `ground` only — icons and ≥17pt labels above that. |
| `Ink.quaternary` | `#6B6866` | `#9B9893` | Never text. Disabled glyphs only. |

**Light-mode elevation runs out of headroom above `raised`.** Beyond it, elevation is material and shadow, never more lightness (§3).

### 2.2 The colour families

Four families. They never borrow from each other, and **none of them is a brand accent** (§2.3).

**Semantic — one meaning each, never decorative.**

| Role | Dark | Light |
|---|---|---|
| `Semantic.success` (sync complete, saved) | `#51C672` 7.6:1 | `#007E17` 4.9:1 |
| `Semantic.destructive` (delete, remove highlight) | `#FF716B` 6.1:1 | `#C20011` 5.9:1 |
| `Semantic.warning` (parse failed, stale feed) | `#E49900` 6.9:1 | `#9E4900` 5.7:1 |

**Highlight — a privileged family, because it is the app's core taxonomy** ([theme 7](design-audit-2026-08.md#7-colour-is-the-apps-core-taxonomy-and-it-is-barely-rendered)). Split into two roles the current code conflates. **Paint** is what sits behind text — unchanged; `HighlightColor.uiColor(darkBackground:)` is protected work and nobody may replace its multiply-on-light / screen-on-dark composite with a plain alpha. **Marker** is the identity chip (swatches, picker circles, Highlights rail, notebook rail) — new, saturated, and where GoodLinks' brightness lives, precisely because it never sits behind text.

| | Marker (both schemes) | Light paint | Dark paint |
|---|---|---|---|
| yellow | `#F9CC21` | `#FCF3BE` | `#7E7858` |
| green | `#43D066` | `#D6F4D6` | `#667966` |
| blue | `#00A5ED` | `#D0E6FC` | `#63717E` |
| pink | `#F6519A` | `#FCDAE8` | `#7E6972` |

Markers carry `Ink.primary` (dark value) glyphs, never white — white-on-yellow is 1.5:1.

**Source — row and kind identity only** (§6). Hues are normalised to our chip lightness so a column reads as one family rather than a logo parade.

| | Dark | Light |
|---|---|---|
| `Source.youtube` | `#E8605B` | `#CF4040` |
| `Source.reddit` | `#DC7200` | `#C45500` |
| `Source.website` | `#3F93F7` | `#1779E1` |

Reddit is pulled to hue 58° rather than its brand 35°: at our lightness the brand value is indistinguishable from YouTube's. The glyph, not the hue, is the primary discriminator.

**System state — no hue at all.** Reading position (TTS) and search matches must never look like a user's highlight. They render as a **luminance wash only** plus a 3pt `Accent.primary` leading rail. A coloured band behind a paragraph means the user put it there; nothing else may claim that signal.

**The wash is paper-relative, and the token is the *step*, not the value** *(amended, ratified by Ellen on the built result of #72)*. The original text gave two literal colours — `#312F2C` dark, `#E9E7E5` light — measured against `Surface.ground`. But the wash's home is the reader, and the reader has eight hand-tuned papers (T1/T2); a fixed `#E9E7E5` band laid over Sepia or Forest is precisely the "coloured band" this section forbids. So:

```
SystemState.washStep = 16/255, applied equally to R, G and B
wash(paper) = paper + step   on a dark page
            = paper − step   on a light page
```

Every channel moves by the same amount, so no hue is introduced on any paper. Over `Surface.ground` this reproduces the two original literals to within 1/255 — they were `#211F1C` + 16 and `#F8F6F5` − 15/15/16 all along — so nothing about the specified appearance changes; what changes is that the rule now holds on all eight papers instead of one. `darkBackground` is the *reader theme's* darkness, not the UI scheme: a light-mode app can be showing a dark paper. The companion rail resolves the same way (`SystemState.railUI(darkBackground:)`).

### 2.3 The accent binding — v1 is neutral

Ellen's question on the v1 draft was **"do we need a brand color yet?"** The answer this document gives is **no**.

**v1 ships true neutrals: no brand accent anywhere.** The neutral ramp, the three semantics, the highlight family and the source hues are the entire palette. Every colour on screen is then either a user's choice, a system state, or a source's identity — which is N3 ("colour that answers nothing gets deleted") applied to the brand itself. A fixed brand hue chosen now would be a colour answering no question.

**`Color.playerPink` retirement stands.** Fully saturated `#FF2D55` is disqualified by N5 wherever you put it. The token is deleted and the audio capsule becomes glass. Pink survives only as `HighlightMarker.pink`, where the user chose it.

**The plumbing is built now, so a later accent is a rebind and not a repaint.** Four tokens. Surfaces reference *only* these — no view ever names a neutral directly for an interactive role.

| Token | Role | v1 dark | v1 light |
|---|---|---|---|
| `Accent.primary` | Glyphs, text, selection marks, unread rails, active toggles, links | `#F2F0ED` (= `Ink.primary`) | `#23201C` (= `Ink.primary`) |
| `Accent.fill` | The one prominent capsule per screen; selection chips | `#F2F0ED` | `#23201C` |
| `Accent.onFill` | Label/glyph on top of `Accent.fill` | `#211F1C` 14.5:1 | `#F8F6F5` 15.1:1 |
| `Accent.muted` | Tinted wash behind a selected row | `#373532` | `#EDEAE8` |

- **A1.** No view may reference `Ink.*` or `Surface.*` for an interactive-state role. Selection, activation, links and unread all go through `Accent.*`. `Ink.primary` inside a `Button`, `Toggle` or selection modifier is a violation.
- **A2.** `Accent.onFill` is never hardcoded to white or black; it is always the token, because its correct value flips with the binding.
- **A3.** Nothing may depend on `Accent.primary` being neutral. No "since the accent is ink, we can reuse it for the divider" shortcuts — that is what turns a rebind back into a repaint.

The v1 result is a high-contrast neutral interface: an ink-filled primary capsule on light, a paper-filled one on dark, ink rails, ink checkmarks. Calm, modern, and deliberate rather than unfinished.

### 2.4 The accent question

**Ellen's preferred direction: a user-selected primary colour, tied to the user's highlight-colour choice, reflected app-wide** — so a reader's palette ties the whole app together (the GoodLinks move, personalised). That is a **feature**, not a palette decision, and it is out of scope for the pretty pass. This section fixes the contract so the feature is cheap when it lands.

**The derivation rule.** The user's accent is never the raw marker value — `#F9CC21` text on white is 1.6:1. The binding takes the marker's *hue* and re-lightens it per scheme:

```
Accent.primary = OKLCH(L: dark 0.74 / light 0.46,  C: min(marker.C, 0.16),  H: marker.H)
Accent.onFill  = Ink.primary(light)  when the fill's relative luminance > 0.35, else Ink.primary(dark)
Accent.muted   = the same hue at L 0.34 (dark) / 0.94 (light), C 0.05
```

Verified across all four highlight hues against `Surface.ground`:

| User picks | `Accent.primary` dark | on ground | `Accent.primary` light | on ground |
|---|---|---|---|---|
| yellow | `#CBA729` | 7.1:1 | `#785100` | 6.6:1 |
| green | `#67C377` | 7.6:1 | `#006E17` | 6.0:1 |
| blue | `#41B6F8` | 7.3:1 | `#005FA5` | 6.1:1 |
| pink | `#F083AC` | 6.7:1 | `#972159` | 7.3:1 |

Every hue clears 6:1 in both schemes and `Accent.onFill` resolves deterministically. **The derivation is the safety mechanism:** users pick a hue, never a value, so no user choice can produce an illegible interface.

**Planned evaluation, in order:**

1. **Ship v1 neutral and live with it.** The honest test of whether a brand colour is needed is whether the app feels unfinished without one after two weeks of real use. Answer that with the app in hand, not in a document.
2. **If it feels flat:** build the user-accent feature above before considering any fixed brand hue. It is more distinctive than a fixed accent, it is already plumbed, and it makes the app's identity the *user's* reading identity — which fits "built by someone who loves reading" better than a house colour does.
3. **A fixed brand hue is the last resort**, and only if the user-accent feature is rejected. The elimination analysis for that case is parked in [Appendix A](#appendix-a-the-fixed-accent-analysis-parked).

**Open question for Ellen** (needed before the feature is built, not before v1): does the app accent follow the user's *most-used* highlight colour automatically, or is it an explicit pick in Settings? Automatic is more magical and more surprising; explicit is more controllable and one more setting.

---

## 3. Surfaces & glass (resolves [theme 1](design-audit-2026-08.md#1-there-is-no-surfaceelevation-system-so-tabs-dont-feel-like-one-app) and [theme 3](design-audit-2026-08.md#3-reader-chrome-does-not-separate-itself-from-content--and-it-fails-asymmetrically-by-scheme))

Today Feeds is `.plain` on `systemBackground` and Highlights is grouped, so two sibling destinations are two different apps:

| Feeds (plain) | Highlights (grouped) |
|---|---|
| ![Feeds light](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/07-feeds-list-light.png) | ![Highlights light](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/26-highlights-populated-light.png) |

**There are exactly four elevations. No fifth.**

| Level | What it is | Fill | Corner | Shadow |
|---|---|---|---|---|
| **E0 — ground** | The page. One per screen. | `Surface.ground` | — | none |
| **E1 — container** | Grouped list container, card, field, note bubble. | `Surface.raised` | 16pt continuous | none in dark; `y2 blur8 α0.05` in light |
| **E2 — modal** | Sheets, popovers, menus. | `Surface.elevated` | system | system |
| **E3 — floating glass chrome** | Anything hovering over scrolling content: nav pills, sidebar affordance, audio capsule, reader toolbars. | system glass, see S4 | 22pt or capsule | the material's own shadow |

- **S1.** Every list is `.listStyle(.insetGrouped)` on `Surface.ground` with `.scrollContentBackground(.hidden)`. Delete every other `listStyle` in the app. One page surface, one container surface — that is the whole system.

  **S1a — the sidebar is FLAT, and is the one exception to S1** *(amended, ratified by Ellen on the built result of PR #73)*. Layer 0 is not a destination list; it is the ground floor the whole app sits on, and it takes `.listStyle(.plain)` on `Surface.ground`. **One continuous ground: no per-section cards, no row containers, no separators.** Section headers and rows sit directly on the ground and whitespace does the separating. The only fill in the list is a **single soft selection wash** (`Accent.muted`, A1) landing directly on the ground — never a pill nested inside a card, and never a second selection treatment for a different row type.

  Ellen, reviewing build 43 against Reeder and Craft: the sidebar "may have too much layering: let's get closer to Reeder and Craft." An inset-grouped sidebar puts a floating `Surface.raised` card under every section, then a selection pill inside that card, on top of the peel card already floating over the sidebar — surface on surface on surface, three deep, for a list of eight rows. The layer model itself (§ wave 4) is unchanged: the list card above keeps its elevation. It is the *internal* layering that is struck.
- **S2. No strokes.** No `.border`, no `.overlay(RoundedRectangle().stroke())`, no `.background(...).cornerRadius()` faking an outline, on any container or control. Separation is the E0→E1 value step plus 16pt of ground (N2).
- **S3. One exception, tightly scoped:** rows *inside* one E1 container may be separated by a 0.5pt `Surface.divider` inset to the text column. This is the only line in the app. It is not a border; it never surrounds anything.
- **S4. Floating chrome is GLASS, and that is not negotiable** *(amended, ratified by Ellen on the wave-5 build)*. Every floating chrome surface — the reader's top nav, the action capsule, the audio capsule, the status pill, the glass circles — takes the **system glass material** (`.glassEffect`), in **both** schemes, with **nothing painted over it**.

  Ellen, on the wave-5 build: *"the capsule and top nav read as way too opaque — we've lost the glass effect that made these elements feel native and dynamic and actually legible as a distinct surface."* That last clause is the rule's whole rationale: **translucency is what makes the surface legible as a surface.** Real glass blurs, dims and desaturates what is behind it, and that live optical difference is what separates chrome from content. A flat wash separates nothing — it just puts a lighter rectangle on the page, and it reads as a slab parked on the article rather than chrome floating over it.

  This strikes S4's original wording, which specified `.regularMaterial` plus a `Surface.chromeTint` overlay (`#262421`/0.35 dark, `#FBFAF8`/0.45 light) as a "material floor". That tint chased a genuine light-mode legibility defect — body text reading through the nav bar — but it fixed it by killing the blur, which cost more than the defect did. **The `Surface.chromeTint` token is deleted.** Content must be visibly blurring through every floating surface, in both schemes; that is the acceptance test, and it is checked on a real article, not on an empty screen.

  Implementation follows **N6**: prefer the current-generation Apple material over a hand-rolled equivalent. Free-floating chrome — capsules, circles, pills — goes through `floatingChrome(in:)`, which is `.glassEffect(.regular,in:)`; it carries its own shadow and its own scheme adaptation, so neither is re-applied. A **system nav bar** cannot take `.glassEffect` (there is no toolbar API for it), so it takes the lightest genuinely-translucent material instead — `.toolbarBackground(.ultraThinMaterial)` with visibility pinned `.visible`, so it is a *surface* rather than nothing, but a surface you can see through. `.regularMaterial` over the reader is out: that is what "too opaque" named.

  Over short/static content (a settings header) an ordinary system material is still fine — this rule governs chrome that floats over scrolling content.
- **S5. Chrome reserves its own space.** Every floating chrome element publishes `its height + 12pt` as a `safeAreaInset(edge:)` on the scroll view. Content never passes under chrome at rest. This is [fix #1](design-audit-2026-08.md#if-we-fix-only-ten-things) stated as a rule.
- **S6. Revealing chrome must not move text.** The inset is reserved whether chrome is shown or hidden. The plain reader already does this with a frozen inset; the block reader must match.
- **S7. Never put a border on only one side of a rounded card.** Ellen's words, verbatim, from the PR #73 review that struck R1: *"never ever add a border to only one side of a rounded card."* This is the general rule the unread rail broke — in an all-unread list the per-row rails merged into one continuous bar hugging the container's rounded left edge, a straight line trying to follow a curve. It is a standing rule, not a note about that one component: leading rails, top hairlines, trailing accents and bottom rules on a rounded container are all the same defect. **A rail is legal only when it sits fully *inside* its card** with the card's own padding around it, and only when it encodes something nothing else does — the Highlights passage rail, which carries the marker colour, is the one built example (H2).

| Light — the S4 defect | Dark — same bar, fine |
|---|---|
| ![Light chrome](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/20-reader-chrome-legibility-light.png) | ![Dark chrome](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/43-reader-chrome-dark.png) |

---

## 4. Typography

### 4.1 The reader is finished work — protected

New York at 18pt / 6pt leading / 12pt paragraph spacing, the eight-theme ink+paper system, the eleven-face catalogue with bundled Atkinson Hyperlegible Next and Lexend — the audit graded all of it *good*. Codified so nobody "improves" it:

- **T1.** Reader body face, size, leading, paragraph spacing, measure and page colour come from the theme + typography settings. No UI agent hardcodes any of them.
- **T2.** The reader canvas may be darker than `Surface.ground`; it may never be lighter in dark mode, or darker in light mode. Entering the reader is a step *into* sanctuary.
- **T3.** Serif faces are legal **only** for reader body content (N4).

### 4.2 The UI type POV: system, everywhere

> **Amended by Ellen's review of PR #73.** The position below — SF Pro under 28pt, Lexend for the display tier — shipped and was rejected on sight:
>
> > "Lexend is not a brand font… either a full typography pad with a real perspective, or keep everything system."
>
> **T4–T6 are superseded.** The display tier is San Francisco bold at the matching text style; no UI surface loads a bundled face. `DisplayType` survives as the *name* of the tier (screen titles, sheet titles, the sidebar header, empty-state titles) so a future pass has one seam, not a scatter of `.font(.largeTitle)` calls.
>
> The unresolved question is not "which bundled face" — it is that this app has no typographic point of view yet, and picking a face off the reading catalogue was a shortcut past that. **A real typography exploration is its own piece of work**; until it happens, system type is the honest default, not a placeholder.
>
> Lexend remains bundled and remains offered in the reader's *reading*-face catalogue (`ReaderFont`). A user-chosen body face for article text is a different thing from a brand face for chrome, and the audit graded that catalogue good.
>
> The superseded reasoning is kept below because the next attempt should know what was already tried and why it failed.

<details>
<summary>Superseded — system for text, one bundled face for display (T4–T6)</summary>

The app already bundles and registers five sans families (`project.yml` → `UIAppFonts`: Lexend, Inter, Geist, Atkinson Hyperlegible Next, plus serif Literata), so "use a bundled face" costs zero new dependencies. The question is only *where*.

**Position: SF Pro for everything under 28pt; one bundled face for display type at 28pt and above.**

- **Below 28pt, no bundled face beats SF Pro and several are worse.** SF ships optical size variants, tuned Dynamic Type metrics at every accessibility step, and correct rendering at 11–17pt, where every row label in this app lives. Inter in particular is close enough to SF at those sizes that swapping it buys no perceptible brand while losing all of the above — a real accessibility regression traded for nothing visible.
- **At display sizes the face is perceptible, and SF reads as "unstyled".** That is where Ellen's "feels unbranded" note actually bites, and where the fix is cheap: screen titles, empty-state titles, the sidebar header, the one large number in an import moment. A handful of short strings.
- **The display face is Lexend.** Already bundled, already vetted by Ellen for the reading catalogue, and a humanist geometric — soft rather than technical, which is the "NOT clinical" side of the brief. Geist is the alternative and is more geometric/precise; it is the natural A/B if Lexend reads too soft at weight. **Taste-check, wave 5.**
- Literata is disqualified for UI by T3/N4. Atkinson stays reserved for its accessibility role — repurposing an accessibility face as decoration is a bad look.

- **T4.** Display tier (≥28pt) is **Lexend**, weight 600, `-0.5` tracking. Everything else is SF Pro. There is no third UI face.
- **T5.** Display type is still Dynamic Type — `Font.custom(_:size:relativeTo:)`, never a fixed size.
- **T6.** If Lexend fails to register, the display tier falls back to SF Pro `.bold` silently. Never a layout change, never a crash.

</details>

### 4.3 The UI scale

Line heights are the face's default for the text style unless stated.

| Role | Face | Style / size | Weight | Colour | Notes |
|---|---|---|---|---|---|
| Display | SF Pro | `.largeTitle` (34) | `.bold` | `Ink.primary` | Screen titles, sidebar header, empty-state titles |
| Display small | SF Pro | `.title2` (28) | `.bold` | `Ink.primary` | Sheet titles |
| Section header | SF Pro | `.subheadline` (15) | `.semibold` | `Ink.secondary` | Sentence case, never all-caps |
| Row title | SF Pro | `.body` (17) | `.semibold` unread / `.regular` read | `Ink.primary` / `Ink.secondary` | 2 lines max |
| Row summary | SF Pro | `.subheadline` (15) | `.regular` | `Ink.secondary` | 2 lines, `lineSpacing 2` |
| Metadata | SF Pro | `.caption` (12) | `.regular` | `Ink.tertiary` | One line, `" · "` joined |
| Button label | SF Pro | `.body` (17) | `.semibold` | per §8.3 | |
| Chip / badge | SF Pro | `.caption2` (11) | `.semibold` | per §8.3 | |
| Field input | SF Pro | `.body` (17) | `.regular` | `Ink.primary` | |

- **T7.** Every string is sentence case except proper nouns: "Add feed", "Import subscriptions", "Line spacing". No Title Case anywhere (the audit found both in one menu), no all-caps labels, no tracked eyebrows.
- **T8.** Any single-line label that can receive arbitrary content gets `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: false)`. The "Saved" badge currently wraps to "Save" / "d":

  ![Saved badge break](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/16-feedentries-savedbadge-break-light.png)
- **T9.** Dynamic Type is supported to `.accessibility3` on every surface. Rows grow; they never truncate the title to preserve metadata. At `.accessibility1` and above, metadata may wrap to two lines and thumbnails drop out.

---

## 5. Iconography

Ellen's note: Apple's default glyphs "look clinical, and we overuse them"; the result "feels unbranded". Both halves are true and they have different fixes. **Clinical** is mostly a *usage* problem — mixed weights, mixed fills, glyphs as decoration. **Unbranded** is a *coverage* problem — there is nowhere in the app that a drawing of ours appears.

**THE ICON SET IS DECIDED: PHOSPHOR** *(ratified by Ellen on the wave-5 build; supersedes the three-way comp)*. Ellen, striking wave 5's hand-drawn marks: *"why are we creating custom line art? I asked for an iconography strategy and suggested a specific library… Use phosphor."* Phosphor is the app's icon substrate. Tabler is out, the comp is cancelled, and **drawing our own line art is banned** — see I9.

**Interim position, until the Phosphor adoption wave lands:** SF Symbols are the substrate, not the personality. They stay for system verbs, they render at one weight and one scale, and the glyph count comes down by roughly half. §5.1–5.2 are written so the swap is mechanical rather than a redesign, and every rule in them survives it — only the source of the artwork changes. §5.4 is the migration.

### 5.1 SF Symbols usage — interim standard

- **I1.** SF Symbols are used for **standard system verbs only**: back, share, add, play/pause, chevrons, search, trash, checkmark. Users read these as OS vocabulary; a custom drawing of "share" is worse than useless. *(Post-migration this rule reads "the icon set is used for standard system verbs only" — the constraint is about which concepts get a glyph, not who drew it.)*
- **I2. One weight, one scale.** Every symbol renders `.medium` weight at `.medium` scale, sized to the adjacent text's optical size. Mixed weights are most of what "clinical" actually means here — as is the audit's "Watch on YouTube" glyph, a filled black rounded rectangle heavier than the nav title beside it.
- **I3. Fill is semantic, never decorative.** Outline = available/inactive. Filled = active/selected/on. Never mixed inside one control group. The one exception is transport controls (`play.fill`, `pause.fill`), where filled is the platform convention for the shape itself.
- **I4.** Symbols are monochrome `Ink.*` or `Accent.primary`. No `.hierarchical`, no `.palette`, no multicolour — multicolour SF Symbols are the strongest "unstyled iOS app" signal there is.

### 5.2 The overuse rule — set-independent

Everything here is about *how many* glyphs exist and *where*, not who drew them. It stands unchanged through the migration, and it is the single biggest thing that makes the migration cheap: the app currently references **28 distinct SF Symbols**, and this section removes a large fraction of them.


- **I5. Glyphs are banned from:** metadata lines, list-row bodies, section headers, menu items, and settings rows. If a text label already carries the meaning, the glyph is decoration and gets deleted (N3).

  This is the general rule behind R2. Library's meta line currently prefixes each field with a symbol (`🕐 33 min`, `▶ Video`, `✏️ 2`) while Feeds uses bare text — we standardised on bare text, and this says why. Settings is the other offender, with three icon treatments in its first three sections: monochrome grey cloud, tinted blue person-key, then no icons at all. **Settings rows get no icons.**

  ![Settings icon treatments](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/28-settings-1-light.png)

- **I6. Icons appear in exactly four places:** nav-bar and toolbar actions, the navigation list, source chips, and empty states. Nowhere else. A fifth place is a rule change, not a design decision.
- **I7. Enclosure rule.** A glyph sits inside a filled circular chip **only when it identifies a thing** (a source, a smart list, a saved search). Actions are never chipped — they get the glass-circle vocabulary (§8.3). This is the GoodLinks distinction, and it is what stops the navigation list becoming coloured-circle soup.
- **I8.** No emoji as UI iconography, ever.

### 5.3 Where we go custom — ONE place

~~**Three places, permanent:** the highlight mark, one line-art mark per empty state, and the source-kind glyphs.~~ **Struck** *(Ellen, on the wave-5 build)*. Wave 5 drew seven custom marks to this spec and shipped them into every empty state and the Highlights row; Ellen deleted them on sight — *"why are we creating custom line art? I asked for an iconography strategy and suggested a specific library."*

- **I9. We do not draw line art. Use Phosphor.** No hand-authored glyph set, no per-empty-state marks, no bespoke UI drawings, however consistent their spec. A glyph the icon set does not have is either composed from glyphs it does have or the concept changes. The old I9 spec (2pt stroke on a 24pt grid, round caps, no fills) survives only as the **harmonisation target** an occasional composite must match — it is not a licence to draw a new one.
- **I10. One exception, and it is not UI: the app's identity mark.** The Highlights identity mark and the app icon are brand assets, commissioned once and drawn deliberately. They are not part of the icon substrate, they are not per-state artwork, and they do not license anything else. **Empty states use the icon set** — 64pt, `Ink.tertiary`, one weight.
- **I10a.** No mascot, no illustration *style*, no spot illustrations.
- **I10b. Source-kind glyphs** (§6) are third-party *brand* marks, not our drawings: normalised to one stroke weight and one optical size so YouTube, Reddit and a website sit in a column as siblings. Unaffected by this rule.

### 5.4 The Phosphor adoption wave (next)

**The set is chosen. This section is now an implementation plan, not a comparison.** Ellen ratified Phosphor on the wave-5 build; the twelve-glyph three-way comp described below is **cancelled**, and Tabler is recorded only as the alternative that lost.

~~**Candidates** (licenses verified 2026-08-03):~~ **Reference** — what was weighed, kept for the record:

| | Tabler Icons | Phosphor |
|---|---|---|
| License | MIT | MIT |
| Count | 6,184 (5,130 outline + 1,054 filled) | 1,248 |
| Weights | outline + filled | 6: Thin, Light, Regular, Bold, Fill, Duotone |
| Design grid | 24×24, 2px stroke | 16×16, scales up |

Each has one structural advantage the other lacks, which is what makes this a real comparison rather than a taste poll:

- ~~**Tabler's 24×24 / 2px grid is already our I9 custom-glyph spec**, so the permanent custom marks sit natively in the set.~~ Moot: the amended I9 deletes the custom marks, which deletes the argument.
- **Phosphor's six weights map cleanly onto both SF Pro's weight range and our I3 outline-vs-fill semantics**, and give the set somewhere to go at Bold Text and accessibility sizes. **This is the winning argument.**

**Evaluation criteria** — all four, in order:

1. **Stroke harmony with our type at real sizes.** Glyphs render at 14pt (small tier), 17pt (standard) and 20pt (prominent) beside SF Pro body text and Lexend display. A 2px-on-24 stroke is heavier than SF Symbols `.medium` at 17pt; whether that reads as confident or clunky next to our type is the first question and it cannot be answered from a specimen sheet.
2. **Coverage of our core glyph set.** The app references **28 distinct SF Symbols** today, and §5.2 will cut that. Both sets trivially cover the common verbs. The risk is Apple's *composite/badged* symbols, which have no third-party equivalent: `note.text.badge.plus`, `person.crop.circle.fill.badge.checkmark`, `play.rectangle.fill`, `textformat.size`, `highlighter`. Each must be matched or composed from two Phosphor glyphs — **not redrawn** (I9). Count them at the start of the adoption wave.
3. **Rendering approach — SF Symbol templates, not plain images.** Third-party SVGs get authored into a custom `.symbolset` via the SF Symbols app's template flow. This preserves Dynamic Type scaling, `.imageScale`, text-baseline alignment inside label runs, weight variants and `symbolRenderingMode`. A plain asset-catalog `Image(...).renderingMode(.template)` loses all of it, and would silently break T9 (`.accessibility3` support) and I2 (scale matched to adjacent text). **Asset images are not an acceptable shortcut.**
4. **Weight degradation.** Whichever set wins, check it at Bold Text and `.accessibility3`. A single-weight source may need a manually thickened variant; a set that only looks right at one size is disqualified.

~~**Decision procedure.** Build a comp rendering 12 glyphs inside real screens, three ways: current SF, Tabler, Phosphor. **Ellen picks.**~~ **Cancelled — Ellen picked Phosphor without it.** The twelve hard glyphs it named are still the right *audit* list for criterion 2: `plus`, `checkmark`, `trash`, `xmark`, `globe`, `photo`, `line.3.horizontal`, `checkmark.circle.fill`, `play.rectangle.fill`, `textformat.size`, `note.text.badge.plus`, `highlighter`.

- **I11. No partial migration.** Until the adoption wave lands, the app stays on SF Symbols end to end. No "just this one glyph from Phosphor" — a mixed set is worse than either pure set. The adoption wave gets its own branch and its own dependency decision (SPM package vs vendored `.symbolset`); it is not smuggled into an unrelated PR.
- **I12.** Phosphor replaces the substrate wholesale in one change. Every rule in §5.1–5.2 carries over unchanged.

---

## 6. Third-party brand representation

Three source kinds (YouTube, Reddit, websites) and a long tail of favicons. The goal is **faithful enough to recognise instantly, in-system enough to sit in a column** — and never so prominent that a third party's brand outweighs the article (N1).

- **BR1. Favicons are the row identity, and they are always tiled.** A favicon renders 20pt centred on a 28pt `Surface.control` tile, 6pt corner. The tile is what makes a ragged collection of transparent PNGs, wrong aspect ratios and near-black logos read as one column. **Never render a bare favicon on the page ground.**
- **BR2. Monogram fallback — a rounded square, not a circle** *(amended, ratified by Ellen on the build-43 review)*. No favicon → the first character of the source title, `.caption/.semibold`, in `Accent.onFill`, on a **28pt rounded square at the 6pt favicon-tile radius**, filled with that source's `Source.*` hue.

  The original rule said *circle*, and that was wrong for the reason BR1 exists: real favicons are small rounded squares, so a column that alternates squares (sites with a favicon) and circles (sites without) is exactly the mixed-fidelity column the tile was invented to prevent. **One geometry, two fills** — real artwork on `Surface.control`, monogram on the source hue. Kind tiles (BR3) take the same geometry, so a group header's mark and a child row's mark are the same shape at the same radius.

  ![Sidebar monograms](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/36-sidebar-open-light.png)

- **BR3. Kind chips use a silhouette, not a logo.** Source-*kind* identity (the YouTube / Reddit / Websites groups) is a monochrome platform silhouette in `Accent.onFill` on a **rounded-square tile** (BR2 geometry) filled with the normalised `Source.*` hue (§2.2). Never the full-colour multi-element logo, never a wordmark, never a logo on a white plate. Today the app mixes all three fidelities in one list — real YouTube brand mark, generic orange speech bubbles for Reddit, system blue globe for websites.
- **BR4. Brand marks never take a prominent slot.** No brand mark on a prominent capsule, in a nav bar's primary position, or at display size. "Watch on YouTube" is a glass circle with a monochrome glyph like every other action — the audit found it as a filled black rounded rectangle, the heaviest element in its nav bar.
- **BR5. Brand hue is row identity only.** It never tints text, selection, controls, or `Accent.*`. A Reddit row is not an orange row.
- **BR6. Platform conventions live in the text, not in more logo.** `r/AskHistorians`, not `AskHistorians`. Cheaper and more faithful than any glyph.
- **BR7. Sanity floor.** Marks are displayed solely to identify the source of user-saved content and to label a link out to it — no endorsement implied, no mark in our own branding, marketing, app icon or onboarding, no recolouring *within* a mark's own silhouette. Any use beyond source identification and link-out is Ellen's decision, not a design agent's.

---

## 7. Sizing: controls, containers, spacing

### 7.1 Control tiers — three, and no more

| Tier | Height | Glyph / label | Use |
|---|---|---|---|
| **Small** | 28pt | 14pt glyph / `.caption2` | Inline chips, tags, swatches, favicon tiles, monograms. **Tap target padded to 44pt** if interactive. |
| **Standard** | 44pt | 17pt glyph / `.body` | Every ordinary tappable control: glass circles, toolbar items, row accessories, list rows. The hit-area floor. |
| **Prominent** | 52pt | 20pt glyph / `.body semibold` | The one primary capsule per screen. |

- **Z1.** 44pt is the minimum hit target for anything tappable, regardless of visual size. Small-tier controls get invisible padding, not bigger art.
- **Z2.** There is no 32pt or 38pt tier. A control that "needs" one is a Standard control with different padding.

### 7.2 Radii and padding

| Element | Radius | Padding |
|---|---|---|
| Screen | — | 20pt horizontal margin |
| E1 container | 16pt continuous | 16pt inner |
| E3 floating panel | 22pt continuous | 16pt inner |
| Pills, capsules, chips | full capsule | 16pt horizontal / 10pt vertical |
| Thumbnails | 8pt | — |
| Favicon tiles, monograms, kind tiles | 6pt continuous — **one geometry, no circles** (BR2, amended) | — |
| List row | — | 12pt vertical |
| Gap between E1 containers | — | 16pt (this gap *is* the separator, per S2) |

- **Z3. Nested radius rule:** an inner radius equals the outer radius minus the padding between them. A 16pt container with 16pt padding holds 8pt-radius children, never another 16pt.
- **Z4.** Continuous corners everywhere (`.rect(cornerRadius:style:.continuous)`). Never `.circular`.

### 7.3 The reader floating action bar is too large — downsize it

Ellen's note, and the measurements confirm it. Current `AudioPlayerBar`: idle is 30pt glyph frames + 13pt vertical padding = **56pt tall** with 24pt horizontal padding; playing is 52pt with a 34pt play button. Over a reading surface that makes it the heaviest object on screen, which is N1 backwards.

| | Now | Target |
|---|---|---|
| Capsule height | 56 idle / 52 playing | **44** in both states |
| Glyph size | `.title3` (20pt) | **17pt** (`.body`) |
| Glyph frame | 30×30 | **24×24** |
| Play button | 34×34 | **30×30** |
| Horizontal padding | 24 / 20 | **16** |
| Vertical padding | 13 / 11 | **10** |
| Waveform height | 30 | **22** |
| Bottom offset | — | **16pt above the safe area** |

A 21% height reduction and a third off the horizontal padding. Paired with C2 (hug width — the capsule is never wider than its contents) and the retirement of the pink tint, the capsule stops competing with the article and becomes chrome that yields to it.

---

## 8. Component contracts

### 8.1 The list row — one grammar (resolves [theme 4](design-audit-2026-08.md#4-the-same-information-class-is-expressed-with-a-different-grammar-in-each-list))

Library and Feeds currently share nothing: two unread signals, two metadata grammars, two source formats, thumbnails in one and not the other.

![Library populated](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/35-library-populated-light.png)
![All Items](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/08-allitems-light.png)

**There is one row component, `ReadableRow`, with declared slots.** Library, All Items, per-feed lists and Search all use it.

```
[ title (2 lines max) ]                              [thumbnail]
[ summary (2 lines, optional) ]                       [ 96×54 ]
[ meta · meta · meta ]
```

- ~~**R1. Unread signal is one thing: a 3pt `Accent.primary` leading rail**, full row height, inset 0. Not a dot, not a colour change, not both. Read rows drop the rail and shift the title to `Ink.secondary`.~~
  **R1 (amended — Ellen's review of PR #73). Unread signal is no added chrome at all.** An unread row is the row at full ink (`.semibold` title, `Ink.primary`, full-strength thumbnail); a read row recedes — `.regular` title at `Ink.secondary`, thumbnail at 0.7. No rail, no dot, no badge.
  Two things killed the rail. In an all-unread list the per-row rails merge into one continuous bar hugging the container card's rounded left edge — *never put a border on one side of a rounded card*. And underneath that: the rail had no articulable job. The title tone already carried the fact.
  The Highlights passage rail is untouched and is the counter-example worth copying: it sits **inside** its card, and it encodes the marker colour, which nothing else does.
- **R2. Metadata is a single `.caption` line, `Ink.tertiary`, fields joined by `" · "`.** No glyphs (I5), no bare spaces. Field order is fixed and identical everywhere: `source · relative date · duration/count`. A field duplicating the screen's nav title is omitted (per-feed lists drop `source`).
- **R3. Source string has one format**, from one helper: `siteName` if present, else host with `www.` stripped. Never three formats in three adjacent rows.
- **R4. Thumbnails are trailing, 96×54, 8pt corner, and every row reserves the slot** when the list can contain them — an empty slot renders `Surface.control`, so rhythm never goes ragged. Library gets thumbnails.
- **R5. Row height is fixed per list at 3 lines minimum.** A row missing summary or metadata pads; it does not collapse.
- **R6. Every row is a real `NavigationLink`** with the system disclosure. No hidden links in a `ZStack`, no `Button`s masquerading as rows. Highlights rows link to the passage.
- **R7. Failure is visible in the list.** A failed-parse article shows a `Semantic.warning` glyph in the meta line — the one glyph I5 permits there, because no text field carries that meaning. You should never learn about a failure by opening it.

### 8.2 Sheets (resolves [theme 6](design-audit-2026-08.md#6-sheets-have-no-shared-contract))

Four dismissal verbs, three heights, three selection idioms today.

| Sheet role | Dismiss verb set | Detent |
|---|---|---|
| **Editor** — changes commit live (Typography, Highlight edit, Tags) | `Done` only, trailing | `.medium`, so you can see what you are changing |
| **Form** — changes commit on confirm (Add URL, Add feed) | `Cancel` leading / `<Verb> object` trailing | `.height(220)`; one field never gets a full screen |
| **Informational** — nothing to commit (Import subscriptions, Settings) | `Done` trailing | `.large` |

- **SH1. Every sheet has a visible dismiss control.** Swipe is never the only exit. (Settings currently has no exit at all.)
- **SH2. One selection idiom app-wide:** a filled `Accent.fill` circle with an `Accent.onFill` checkmark, trailing. Not a ring here, a check-in-swatch there, blue text elsewhere.
- **SH3. Confirm verbs are verb + object**: "Add feed", "Save link". Never "OK", never a bare "Subscribe" when the sibling sheet says "Save".
- **SH4. Explanatory subtitles are never tinted.** If a row is a `Button`, its subtitle is explicitly `Ink.secondary` — the Import sheet paints its own explanation blue:

  ![Import](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/31-youtube-import-light.png)
- **SH5. An editor sheet shows the thing it edits — but it never REPEATS what is already on screen** *(amended, ratified by Ellen on the wave-5 build)*. Where the thing being edited is off-screen or covered, the sheet renders it. Where the sheet is presented *over* the thing at a partial detent, the sheet must not draw a second copy of it. **The highlight sheet is the named case: it does not render the quoted passage.** The quoted text was deleted from that sheet once already; wave 5 resurrected it on an SH5 reading Ellen struck — *"we previously removed highlighted copy of the text from the highlight sheet because it is unnecessary, the same text is literally right there on screen."* The `.medium` detent exists precisely so the passage stays visible behind the sheet.

  **The general lesson, and it is not about this sheet:** before adding UI, check whether it was previously removed. `git log` is the record of what has already been decided. Re-litigating a settled deletion from first principles costs a review round every time.

### 8.3 Floating chrome, pills and buttons

Seven button vocabularies today. **There are three.**

| Vocabulary | Shape | Use |
|---|---|---|
| **Glass circle** | 44pt circle, system glass (S4), `Ink.primary` glyph | Every nav-bar and floating single action: back, add, mark-all-read, sidebar affordance. |
| **Glass capsule** | 44pt tall, system glass (S4), hug width (C2) | Multi-glyph clusters and the audio capsule (§7.3). |
| **Prominent capsule** | `Accent.fill`, `Accent.onFill` label, `.body/.semibold`, 52pt | The one primary action on a screen. Max one. |

- **C1.** Plain tinted text as a button is banned. "Export all articles" and "Save key" become prominent capsules or rows with disclosure.
- **C2. The capsule is HUG width** *(amended, ratified by Ellen on the wave-5 build)*. It is exactly as wide as the controls it holds, in every state. Wave 5 read the original C2 — "the capsule has one width", reserving the playing-state width at idle — as *fill the reading measure*; Ellen struck that: *"the capsule should be 'hug' width not a fixed width; revert that change it looks very strange."* A four-glyph cluster stretched across the measure stops reading as a floating control and starts reading as a bottom toolbar, which is the opposite of what §7.3 is for. Idle and playing are two widths of the same hugging object, and the resize is one §10 Standard spring.
- **C3. The capsule is state-aware.** On an article with no content it offers Retry and Share only — not Play.
- **C4.** Chrome over the reader obeys S4, S5, S6 and §7.3. No exceptions for "just this one bar".

### 8.4 Highlight rendering

- **H1.** Any place a highlight colour is shown, it is shown *in colour*, as a 20pt marker circle. The text-list picker ("Yellow / Green / Blue / Pink") is deleted; the swatch row is the only picker component.

  | Delete this | Keep this |
  |---|---|
  | ![Colour menu](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/22-highlight-colormenu-light.png) | ![Edit sheet](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/23-highlight-editsheet-light.png) |
- **H2.** In the Highlights list and notebook view the colour is a **4pt full-height leading rail** in the marker colour, not an 8pt dot. Quote leads; source metadata follows beneath at `.caption` / `Ink.tertiary`. Content first.
- **H3.** Highlights group by article, one header per article.
- **H4.** Highlight paint applies instantly on selection. Never animated (§10).
- **H5.** Reading position and search matches use the system-state family only (§2.2).

### 8.5 Empty states

`Site Logins` is the template — centred, and it explains the mechanism that would fill the void rather than naming the void.

![Site Logins](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/30-sitelogins-empty-light.png)

- **E1.** `ContentUnavailableView` is always an `.overlay` on the scroll view, centred in the viewport. Never a list row, never boxed in a card. (Three placements exist today.)
- **E2.** Structure: a 64pt mark **from the icon set** (I9 — never hand-drawn), display-small title, one sentence naming the mechanism, and — if the copy names an action — that action as a prominent capsule.
- **E3.** Failure states get `Semantic.warning`; empty states get no colour at all.

### 8.6 The typography sheet

~~**The bento grid.** Reserved for exactly one surface: the reader's typography/appearance picker. Mixed-size tiles on `Surface.raised`, each a live self-illustrating preview.~~ **Struck** *(Ellen, on the wave-5 build)*: *"the bento box concept is not landing, and just makes the text size (the one thing people are most likely to change?) most difficult to manage by making its scale smaller."*

**The typography sheet is a plain grouped list, and text size leads it.** There is no bento grid anywhere in the app. A spatial panel allocates its biggest tiles by visual interest, which put theme and face — chosen once — above the fold and squeezed the control people touch constantly into a half-width cell. The list allocates by frequency instead.

![Typography sheet](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/13-typography-sheet-light.png)

- **B0. Text size is the sheet's primary control.** First section, full measure, with a live specimen in the chosen face at the chosen size. Nothing sits above it and nothing sits beside it. **A control's prominence follows how often it is used, not how interesting it is to draw.**
- **B1.** No paper-swatch fans, no page curls, no textures (N4). The live preview *is* the decoration.
- **B2.** Numeric controls put their value trailing the control, never on their own row. One slider treatment app-wide: bare track, trailing value.
- **B3.** The sheet opens at `.medium` so the article stays visible while being tuned. Read Aloud lives in Settings only — the duplicate is removed here.

---

## 9. Playfulness budget

Playfulness is **attention direction with a personality**, and the budget is deliberately small: "inviting, rather than needy or performative" (N3). It is spent in four moments and no more.

1. **Source identity chips** (§6). The GoodLinks icon-chip dialect, and genuinely high-utility: the only way to tell a subreddit from a channel at a glance.
2. ~~**The unread rail** (R1). The most-repeated colour event in the app, so it stays a rail and never a badge.~~ **Withdrawn** with R1 (PR #73 review). The budget line is unspent, not respent — read/unread is now a tone shift and costs no playfulness at all.
3. **Save confirmation.** When a link lands from the share sheet, the new row enters with the §10 attention spring. (The original rule flashed the row's rail `Semantic.success`; with R1 amended there is no rail, so a future implementation needs a different carrier — unbuilt either way.)
4. **First-run import moments** (YouTube subscription import, feed add). A live count ticking up as sources land. Numbers moving is the whole effect.

**The NOT list, straight from the brief:** no confetti, no badge counts that beg, no bounce, no mascot, no illustration style, no washi tape, no paper textures, no page curls, no drop caps, no serif chrome, no gradient text, no rainbow accent rings, no multicolour SF Symbols, no skeuomorphism, no sound. Nothing decorative that answers no question (N3).

---

## 10. Motion

"Smooth and beautiful… everything feels intentional" is a requirement, not a nice-to-have.

| Class | Curve | Use |
|---|---|---|
| **Micro** | `.easeOut(duration: 0.18)` | Tint changes, checkmarks, toggle states, glyph swaps. |
| **Standard** | `.spring(response: 0.34, dampingFraction: 0.88)` | Chrome reveal/hide, row insert/remove, capsule reshaping, sheet content, sidebar open/close. Damping 0.88 settles without overshoot. |
| **Attention** | `.spring(response: 0.28, dampingFraction: 0.72)` | The four playful moments in §9 only. The only curve with any overshoot, capped there. |
| **Navigation** | system default | Push, pop, sheet present. Never overridden. |

- **M1. Never animate:** reader body text layout, font-size or line-spacing changes (apply instantly — animating reflow makes text crawl), scroll position restore, highlight paint appearance, list content on first appear.
- **M2. Chrome reveal fades and scales from 0.96; it never slides content** (S6). No animation exceeds 0.4s; no bounce, no elastic, no curve outside the table above.
- **M3. Reduce Motion is not optional.** Every Standard and Attention animation degrades to a 0.15s crossfade. Springs are wrapped so this is one check, not one per call site.
- **M4.** Haptics pair with the Attention class only: `.success` on save, `.selection` on highlight-colour change. Nowhere else.

---

## 11. Phase-3 wave plan

Six waves, each independently mergeable and reviewable. Wave 1 gates everything (all consume the tokens); waves 2 and 3 are independent of each other; wave 4 consumes 1–3; wave 5 is polish over settled structure; wave 6 is last by instruction and by dependency.

**Already filed elsewhere — excluded from every wave:** [#63](https://github.com/elliebartling/read-later/issues/63) content-fidelity batch (audit theme 8, fix #10) and [#64](https://github.com/elliebartling/read-later/issues/64) block-reader reading-position restore (theme 5, fix #8). Both are correctness bugs, not design work.

**[#57](https://github.com/elliebartling/read-later/issues/57) is resolved: Ellen adopted the sidebar as the default navigation.** It is no longer a gate; it is wave 4.

### Wave 1 — Ground

*Tokens, surfaces, sizing standards. The app stops being a collage.*

| Item | Ref | Kind |
|---|---|---|
| Ship §2.1–2.2 as a token file; delete `Color.playerPink` | theme 2 | code |
| Accent plumbing: `Accent.primary/fill/onFill/muted` bound to neutrals (A1–A3) | §2.3 | code |
| One list style app-wide; delete every ad-hoc `listStyle` | theme 1, fix #2 | code |
| ~~Reader chrome to `.regularMaterial` + chromeTint, both schemes~~ → **struck by the amended S4: system glass, both schemes** | theme 3, fix #1 | code |
| `safeAreaInset` for every floating chrome element (S5, S6) | theme 3 | code |
| Strip every stroke/border (S2); introduce E0–E3 | theme 1 | code |
| Sizing standards: control tiers, radii, padding (§7.1–7.2) | §7 | code |

**Taste-check:** the ground values, and whether v1-neutral reads as deliberate or unfinished — that judgment feeds §2.4 step 1.

### Wave 2 — Grammar

*One row, one meta line, one empty state, half the glyphs.*

| Item | Ref | Kind |
|---|---|---|
| `ReadableRow` with declared slots; adopt in Library, All Items, per-feed, Search | theme 4, fix #9 | code |
| One metadata grammar (R2), one source-string helper (R3) | theme 4 | code |
| Thumbnail slot always reserved; Library gets thumbnails (R4) | Library | **taste-check** |
| `lineLimit`/`fixedSize` sweep; fixes the "Save"/"d" wrap | fix #3 | code |
| Hanging indents, list-item spacing, inline-code treatment in the block reader | fix #4 | code |
| Iconography overuse sweep: strip glyphs from meta lines, settings rows, menus (I5) | §5.2 | code |
| SF Symbol weight/scale/fill normalisation (I2–I4) | §5.1 | code |
| Empty-state template (E1–E3) with placeholder marks | multiple | code |

### Wave 3 — Colour & source identity

*The taxonomy finally renders; sources become recognisable.*

| Item | Ref | Kind |
|---|---|---|
| Marker/paint split; add `HighlightColor.marker` | theme 7 | code |
| Delete the text-only picker; one swatch component everywhere (H1) | theme 7, fix #5 | code |
| Spoken-paragraph tint → system-state wash + rail (H5) | theme 7, fix #6 | code |
| Highlights list: rail, content-first hierarchy, group by article, tap through (H2, H3, R6) | fix #7 | code + **taste-check** on the group header |
| Semantic roles applied (success / destructive / warning) | theme 2 | code |
| Favicon tiles + monogram fallback (BR1, BR2) | §6 | code |
| Kind chips: three brand silhouettes at one stroke weight, normalised hues (BR3, I10b) | §6 | **taste-check** |

### Wave 4 — Navigation

*The sidebar becomes the app. Highest-visibility structural change; consumes waves 1–3.*

| Item | Ref | Kind |
|---|---|---|
| Sidebar becomes the default navigation; the flag becomes an opt-out or is deleted | #57 | code + **taste-check** on flag disposition |
| Nav restructure: list views' Settings gear becomes the back-to-sidebar affordance; no separate floating sidebar button; Settings lives in the sidebar | #57 | code |
| Sidebar visual cleanup to constitution standards: one separator inset (S3), `ReadableRow` grammar, wave-3 kind chips, display-tier header, selection via `Accent.muted` at every level | audit "sidebar experiment" | code |
| Retire or re-scope the tab bar; reconcile deep links and `readlater://` routing with the new root | — | code |

The sidebar's IA was already the best in the app; everything here brings prototype-grade execution up to the constitution — chaotic separator insets (four different left insets in one list), selection styling on only one row type, and a trigger button style used nowhere else.

| Closed | Open |
|---|---|
| ![Sidebar closed](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/34-sidebar-closed-light.png) | ![Sidebar open](https://raw.githubusercontent.com/elliebartling/read-later/main/audit/36-sidebar-open-light.png) |

### Wave 5 — Chrome & delight

*Polish over settled structure.*

| Item | Ref | Kind |
|---|---|---|
| Reader action bar downsizing (§7.3) + hug capsule width + state-awareness (C2, C3) | §7.3 | code |
| Sheet contract: verbs, detents, dismiss controls (SH1–SH5) | theme 6 | code |
| Button vocabulary 7 → 3 (§8.3) | button inventory | code |
| ~~Display type: adopt Lexend ≥28pt (T4–T6)~~ → **a real typography exploration** (T4–T6 superseded; system type until then) | §4.2 | **taste-check**, own piece of work |
| ~~Custom glyph set: highlight mark + five empty-state marks (I9)~~ → **struck; iconography is Phosphor (§5)** | §5.3 | — |
| ~~Typography sheet → bento grid (§8.6)~~ → **struck; simple list, text size first (B0)** | typography sheet | code |
| Restore genuine glass on all floating chrome (S4) | S4 | code |
| Settings: dismiss control, no row icons, de-duplicate Reader / Read Aloud | Settings | code |
| Motion pass: §10 curve tokens, Reduce Motion wrapper, the four playful moments | §9, §10 | **taste-check** on save confirmation |

### Wave 6 — The Phosphor pass

*Last, per Ellen, and now unblocked: the set is chosen (§5.4). Every earlier wave touches icon call sites, so migrating before they settle means churning every glyph twice. Own branch, own dependency decision (I11).*

| Item | Ref | Kind |
|---|---|---|
| ~~Build the twelve-glyph three-way comp~~ → **cancelled; Ellen ratified Phosphor** | §5.4 | — |
| Decide the dependency shape: SPM package vs vendored `.symbolset` | §5.4 / I11 | code |
| Audit the composite/badged symbols with no Phosphor equivalent; match or compose from two glyphs | §5.4 criterion 2 | code |
| Author the chosen set as a custom `.symbolset` via SF Symbols templates — never plain asset images | §5.4 criterion 3 | code |
| Wholesale substrate swap (I12); verify at Bold Text and `.accessibility3` | §5.4 criterion 4 | code |

Runs only after wave 5. Nothing in waves 1–5 may ship a third-party glyph (I11).

---

## Appendix A: the fixed-accent analysis (parked)

Kept because the elimination logic is the expensive part, and it stays valid if a fixed brand hue ever returns (§2.4 step 3).

A fixed accent must be legible on warm charcoal *and* warm near-white, and must not collide with the four highlight hues (which own yellow, green, azure and pink) or the three source hues (which own red, orange and blue). That eliminates yellow, green, blue, pink, red and orange — most of the wheel. What survives is violet/indigo and teal/cyan; cyan reads as GoodLinks' signature, leaving violet-indigo.

The worked candidate was **Iris**, OKLCH hue 293°: `#9D84EC` dark (5.4:1 on ground) / `#663CBC` light (6.6:1 on ground, white-on-it 7.2:1), with `Accent.muted` at `#393350` / `#EBE8FE`.

Two reasons it is parked rather than adopted: it answers no question the user is asking (N3), and it competes for the same slots the user-accent feature wants — shipping Iris first would make a personalised accent feel like a downgrade rather than an unlock.

---

## Compliance

A UI change is compliant when: it uses only §2 tokens and reaches interactive colour only through `Accent.*`; it sits at one of the four §3 elevations; it adds no stroke; it reserves inset for any floating chrome; it uses a §7 control tier and radius; it uses `ReadableRow` if it is a row; it adds no glyph outside the four places in I6; it uses a §10 curve if it animates; and it looks correct in both schemes at `.accessibility3`. If a task seems to need a rule that is not here, the rule is missing — raise it rather than inventing one locally.
