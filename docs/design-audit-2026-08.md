# Design audit — full-app visual inventory (pretty-pass phase 1)

**Date:** 2026-08 · **Build:** Debug, `main` @ `bcb1736` · **Device:** iPhone 17e simulator, iOS 26
**Scope:** descriptive audit only. No product code changed. This document + the screenshots under [`audit/`](../audit) are the entire diff.

Every screenshot below is a real capture of the app running with real content: 3 feeds spanning all three source kinds (a website via RSS, a YouTube channel, a subreddit), 3 saved articles (a long technical blog post, a YouTube video, a Reddit post), 2 highlights with a note, and 1 tag. Empty states were captured separately before seeding.

Screenshots are embedded from the branch, so they render before merge:
`https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/<file>`

---

## How to read this

Each surface is graded on one axis: **how much does it hurt, and does it hurt because of a decision or because of drift?**

| Grade | Meaning |
|---|---|
| **good** | Deliberate, well-executed, keep it and extract the pattern |
| **fine** | Works, unremarkable, no action needed for the pretty pass |
| **inconsistent** | Works, but contradicts how the same idea is expressed elsewhere |
| **jarring** | Actively wrong on screen: illegible, broken, or content-destroying |

The app grew fast through parallel agent sessions, so drift is expected and is most of what follows. What matters for a design language is not the count of defects but **which decisions were never made once and applied everywhere**. That is the [Cross-cutting themes](#cross-cutting-themes) section, and it is the part worth arguing about.

---

## The short version

The reading surface has had real design investment and it shows. The typography — New York at 18pt with 6pt leading and a medium measure, the theme swatch system, the eleven curated faces including bundled OFL accessibility fonts — is the work of someone who cares about reading. The dark reader is genuinely lovely. The TTS waveform is a small piece of craft.

Everything **around** the reading surface is a collage. Four tabs use three page backgrounds. Two lists of "things to read" use different metadata grammars. The same "pick a highlight colour" action has two different pickers, one of which shows no colour. Sheets close with four different verbs. There are five distinct button vocabularies. And the chrome that floats over the reader is transparent enough in light mode that body text renders straight through the article title.

The single highest-leverage decision is not a fix, it is a choice: **the sidebar experiment, hidden behind a Settings flag, has better information architecture and better source identity than the shipping tab bar.** Resolve that first; a lot of the rest follows from it.

---

## Cross-cutting themes

These are the systemic issues. A design-language document has to decide each of them once.

### 1. There is no surface/elevation system, so tabs don't feel like one app

Library, Feeds and Search use `.listStyle(.plain)` on `systemBackground`. Highlights uses the default grouped style. The result: switching from Feeds to Highlights changes the page background from pure white to grey-with-a-white-card, and in dark mode from pure black to black-with-a-dark-grey-card. Nothing about the content justifies the change; it is an unset modifier.

The deeper issue is that the app has no answer to "what is a page, what is a container, what is elevated". Pure `#FFF` / `#000` pages with hairline separators is a valid answer. Grouped cards is a valid answer. Having both, chosen per-file, is not.

| Feeds (plain) | Highlights (grouped) |
|---|---|
| ![Feeds light](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/07-feeds-list-light.png) | ![Highlights light](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/26-highlights-populated-light.png) |

| Feeds dark | Highlights dark |
|---|---|
| ![Feeds dark](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/41-feeds-list-dark.png) | ![Highlights dark](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/40-highlights-populated-dark.png) |

**Decide:** one page surface, one container surface, one elevated surface, in both schemes. Then delete every ad-hoc `listStyle`.

### 2. Accent colour has no system — pink appears exactly once, and it is the loudest thing in the app

`Color.playerPink` is `#FF2D55` at full saturation, applied as a tinted glass capsule. It appears on exactly one surface: the reader's floating player. Everywhere else the accent is system blue (tab bar, unread dots, "All Items" icon, tag rows, Site Logins glyph, sliders), with green for sync-success, red for destructive, orange for archive, and brand colours (YouTube red, Reddit orange) in the sidebar.

So the app's single most saturated, most memorable colour is used for secondary actions on one screen, and the brand's actual accent is Apple's default blue. That is backwards. Either pink is the brand and it should appear in the tab bar, the unread dots and the highlight affordances, or it is not and the player should be neutral.

![Reader chrome light](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/20-reader-chrome-legibility-light.png)

**Decide:** the accent, its saturation, and the semantic roles (interactive / selected / destructive / brand). Right now there are at least six colours doing accent duty with no rule.

### 3. Reader chrome does not separate itself from content — and it fails asymmetrically by scheme

In light mode the glass nav bar is transparent enough that article body text renders straight through it. In the capture below, "from the render they were defined in. That helps prevent bugs but in some cases can be annoying. For those cas" is fully legible *behind* the title "A Complete Guide to useEffect…". Two competing runs of text at similar weight in the same 90pt band. The title loses.

The same bar in dark mode is fine, because a dark glass over dark text has enough separation. This is a **light/dark parity defect**, not a general one, which makes it easy to miss.

Compounding it: neither the top bar nor the bottom player reserves any content inset, so body text runs underneath both. In several captures a line is bisected mid-word by the pink capsule.

| Light — title unreadable | Dark — same bar, fine |
|---|---|
| ![Light chrome](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/20-reader-chrome-legibility-light.png) | ![Dark chrome](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/43-reader-chrome-dark.png) |

**Decide:** the material and opacity floor for floating chrome over long-form text, and whether chrome overlays content or insets it. (Also: revealing the chrome in the block reader *pushes* the text down by ~130pt, so the article jumps under your eyes. The plain reader deliberately avoids this with a frozen inset. See theme 5.)

### 4. The same information class is expressed with a different grammar in each list

Two lists show "things you might read". They share nothing:

| | Library row | Feed entry row |
|---|---|---|
| Unread signal | title colour only | leading blue dot **and** title colour |
| Metadata | SF Symbol + text labels (`🕐 33 min`, `▶ Video`, `✏️ 2`) | bare text, space-separated, no icons, no interpuncts |
| Thumbnail | never | when available, 88×49 trailing |
| Summary | never | 2 lines when available |
| Disclosure | hidden `NavigationLink` in a `ZStack`, so no chevron | none (a `Button`) — but the *same* `ArticleRow` in Search **does** get a chevron |
| Source | `siteName ?? host` — so "YouTube" here, "overreacted.io" there, "www.reddit.com" elsewhere | feed title |

![Library populated](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/35-library-populated-light.png)
![All Items](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/08-allitems-light.png)

The metadata row is the sharpest instance. Library uses icon+label pairs; Feeds uses bare text with 10pt gaps and no separators, so "AskHistorians  3 hours ago  /u/J2quared" reads as three floating fragments rather than one meta line.

**Decide:** one row component with declared slots (thumbnail? unread? summary? meta?) and one metadata grammar (icons or interpuncts, pick one).

### 5. The two readers have already diverged in ways `AGENTS.md` predicted

`AGENTS.md` warns that a fix landed in one reader silently regresses in the other. That has now happened to a feature, not just a fix:

- **Reading-position restore is dead in the default reader.** `initialCharacterOffset` and `onTopCharacterOffset` are wired only into `HighlightableTextView` (the plain reader). `BlockReaderView` receives neither. Since `useBlockReader` defaults to `true`, the shipping experience never restores your place — the article always opens at the top. The state is still being written to `Article.readingCharacterOffset`; nothing reads it back.
- **Chrome reveal shifts content in the block reader** and does not in the plain reader, for the same reason (the plain reader pins a frozen inset; the block reader has no equivalent).
- **The tap-to-reveal-chrome target has dead zones.** In the block reader, taps land on the per-block text views, so the outer margins and inter-block gutters do nothing. Combined with chrome starting hidden, a reader can tap the margin repeatedly and find no way out of the article.

**Decide:** whether both readers survive. If the block reader is the default, the plain reader is a fallback for block-less articles and should be feature-matched or the flag should go. Shipping "Block reader (beta)" as the on-by-default path is also a trust problem in itself.

### 6. Sheets have no shared contract

Across seven sheets there are four dismissal verbs, three heights, and three selection idioms:

| Sheet | Dismiss | Height | Selection idiom |
|---|---|---|---|
| Add URL | `Cancel` / `Save` | full | — |
| Add Feed | `Cancel` / `Subscribe` | full | — |
| Typography | `Done` | full | ring around swatch |
| Highlight edit | `Done` | `.medium` | checkmark inside swatch |
| Tags | `Done` | full | blue text + blue checkmark |
| Import Subscriptions | `Close` | full | — |
| Settings | *(none — swipe only)* | full | — |

Settings having no dismiss control at all is the worst of these: it is a `.sheet`, it has no Done button, and the only exit is a swipe a user has to guess at.

The full-height sheets are also mostly empty. Add URL and Add Feed are one text field each, presented at full screen height with ~1800pt of void beneath.

| Add URL — one field, full height | Import — subtitle painted as interactive |
|---|---|
| ![Add URL](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/15-addurl-sheet-light.png) | ![YouTube import](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/31-youtube-import-light.png) |

**Decide:** dismissal verb per sheet role (destructive-capable → Cancel/Confirm; editor → Done; informational → Close), and a detent policy (single-field sheets get `.height(…)`, control panels get `.medium` so you can see what you're changing).

### 7. Colour is the app's core taxonomy and it is barely rendered

This is a highlighting app. `HighlightColor` has four cases with carefully tuned light/dark composites — the multiply-on-paper and screen-on-dark maths in `HighlightColor.uiColor(darkBackground:)` is genuinely thoughtful. On screen the highlights themselves look great.

But:
- The **edit-menu colour picker is a text list**: "Yellow / Green / Blue / Pink", no swatches at all.
- The **sheet colour picker is a swatch row**, four filled circles. Same action, same model, two pickers.
- In the Highlights tab the colour is an **8pt dot**.
- The TTS **spoken-paragraph tint is a pale yellow band** — visually identical to a yellow highlight. Reading position and user annotation share a colour language, so while listening you cannot tell your highlights from the cursor.

| Edit menu — no colour | Sheet — swatches |
|---|---|
| ![Colour menu](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/22-highlight-colormenu-light.png) | ![Edit sheet](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/23-highlight-editsheet-light.png) |

**Decide:** one colour-picker component, and a reserved colour for transient system state (reading position, search match) that can never collide with user highlight colours.

### 8. Content fidelity failures read as design failures

The reader is only as good as what reaches it, and several things reaching it are broken in ways a user will read as "this app is sloppy":

- **YouTube transcripts have mangled, doubled timestamps glued to the text**: `0:000 secondsC'est le graphique…`, `0:033 secondsIl est frais…`, `0:1212 secondsOn dirait…`. Every video article is unreadable prose.
- **Raw HTML leaks into body text**: a literal `</p>` rendered as content mid-article.
- **Raw RSS boilerplate leaks into feed summaries**: `submitted by /u/J2quared [link] [comments]` shown as the entry summary on every Reddit link post, directly above a meta row that already names the same author.
- **Code blocks vanished** on a code-heavy tutorial. The renderer supports `.preformatted` with a proper monospaced bordered container, so this is an extraction-side loss — but the visible result is prose referring to code that isn't there ("Here's a counter. Look at the highlighted line closely:" followed immediately by the next paragraph).
- **Reddit self posts fail to parse entirely**, landing on "Couldn't parse this page" despite the RSS entry carrying the post body as `capturedHTML`.
- **Inline code gets no treatment** — `useEffect(fn, [])` renders as plain serif prose.
- **Article titles keep their site suffix** ("A Complete Guide to useEffect — overreacted") and then the site is printed again on the next line.

![Video transcript cruft](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/12-reader-video-chrome-light.png)
![RSS cruft](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/32-feedentries-reddit-light.png)

**Decide:** whether extraction quality is in scope for the pretty pass. It probably has to be — no amount of typography rescues a page of `0:1212 seconds`.

---

## Per-surface findings

### Library

| | |
|---|---|
| ![Library empty](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/01-library-empty-light.png) | ![Library populated](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/35-library-populated-light.png) |

**Empty state — inconsistent.** Copy is good ("Share links from Safari, or tap + to paste one."), but the `ContentUnavailableView` is a `List` row, so it sits high under the title instead of centred in the viewport. Search's equivalent is an `.overlay` and *is* centred. Two placements for the same component. No action button despite the copy naming one.

**Populated — inconsistent.**
- No thumbnails, while feed rows have them.
- Row height varies with metadata availability and there is no placeholder, so the failed Reddit article collapses to two lines between two three-line rows. Ragged vertical rhythm.
- A failed article is indistinguishable from a healthy one in the list; you only discover the failure by opening it.
- No reading-progress indicator despite the app tracking progress and a 90 % read threshold.
- `siteName ?? host` produces three different formats in three adjacent rows: `www.reddit.com`, `overreacted.io`, `YouTube`.

**Dark — fine.** Pure black page. The read-state title in `.secondary` grey on `#000` is low contrast (approximately 3.5:1); read items get noticeably harder to scan.
![Library dark](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/39-library-populated-dark.png)

### Feeds — flat list

![Feeds list](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/07-feeds-list-light.png)

**inconsistent.**
- **No source identity.** A YouTube channel, a subreddit and a text blog render identically; the only cue is the host string. The app models three source kinds explicitly and shows none of it. (The sidebar experiment solves exactly this — see below.)
- **"All Items" and subscription rows don't share a grid.** All Items has a leading icon and an inset separator; subscription rows have no icon and a full-bleed separator. The text columns start at different x. Visible discontinuity two rows apart.
- The Reddit feed titles itself `AskHistorians`, dropping the `r/` convention that makes it recognisable.
- The `+` menu mixes capitalisation: "Add Feed…" (title case) vs "Import subscriptions…" (sentence case), and the latter wraps to two lines in the menu.

![Add menu](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/05-feeds-addmenu-light.png)

**Empty state — fine.** ![Feeds empty](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/02-feeds-empty-light.png)

### Feeds — All Items river

![All Items](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/08-allitems-light.png)

**jarring** (because of the RSS cruft) / **inconsistent** (everything else).
- `submitted by /u/X [link] [comments]` rendered as the summary, with the same username repeated in the meta row below.
- Density is very low: three-line titles plus two-line summaries plus meta yields about five items per screen for an 88-item unread river.
- The river is chronological only, so a single high-volume feed dominates it entirely. No interleaving, no grouping, no per-source balance.
- Meta row has no interpuncts; three fields float with equal spacing.
- The floating tab bar overlaps the last row with no bottom content inset, so a row is permanently half-legible through glass.

### Feeds — per-feed entries

| YouTube (thumbnails) | Reddit (no thumbnails) |
|---|---|
| ![YouTube entries](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/09-feedentries-youtube-light.png) | ![Reddit entries](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/32-feedentries-reddit-light.png) |

**jarring.** The "Saved" badge has no `lineLimit`/`fixedSize`, so on a read row it wraps mid-word — literally rendering **"Save" / "d"** on two lines — and squeezes the feed name into truncation:

![Saved badge break](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/16-feedentries-savedbadge-break-light.png)

Also:
- Inside a single channel's list, every row prints the channel name again (the `author` field), duplicating the nav title on all 14 rows. `showsFeedName` is correctly suppressed; `author` is not.
- Consequently the meta field **order changes** between All Items (`feed · date · author`) and per-feed (`date · author`) for the same component.
- Thumbnails are 88×49 against rows 100–140pt tall, leaving a ragged right edge of dead space, and carry no play badge or duration despite being video.

### Reader — block reader (default)

| Top | Heading + divider |
|---|---|
| ![Block reader top](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/17-blockreader-top-light.png) | ![Heading](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/18-blockreader-heading-code-light.png) |

**good** on body typography. New York at 18pt, 6pt leading, 12pt paragraph spacing, medium measure. Comfortable, well-balanced, correct measure for the device. Headings carry real scale and weight contrast. The `.divider` block renders as a short centred rule — a nice touch. Dark mode is excellent: `#0F0F0F` page, `#EBEBEB` ink, no glare.

![Reader dark](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/42-blockreader-dark.png)

**inconsistent / jarring** on structure:
- **List items have no hanging indent.** Wrapped lines align under the bullet rather than under the text, so multi-line list items lose their shape entirely. Most visible defect in the type system.
- List item spacing equals paragraph spacing, so a list doesn't read as a group.
- **The article header is content-dependent, not chrome.** The YouTube article got a hero image, a serif title and a byline; the blog post got none — it opens straight into body copy with no title anywhere on the page. Whether you can see what you're reading depends on what the extractor returned.
- Inline code is undifferentiated.
- Reading position never restores (theme 5).

### Reader — video article

![Video reader](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/12-reader-video-chrome-light.png)

**jarring.**
- Transcript timestamps are doubled and unspaced (theme 8).
- **Tapping the video hero opens an image zoom viewer, not the video.** A 16:9 still with a play-shaped subject that zooms instead of plays is an affordance lie. ![Image zoom](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/11-imagezoom-viewer-light.png)
- The "Watch on YouTube" toolbar glyph is a filled black rounded rectangle — the heaviest element in the nav bar, heavier than the title, and stylistically unlike every other SF Symbol there.
- Subtitle reads "33 min left", which is transcript *reading* time presented where a viewer expects video duration.
- Immersive default hides chrome, so the article opens with no back button and no status bar: ![Video immersive](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/10-reader-video-immersive-light.png)

### Reader — failed parse

![Failed parse](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/33-reader-reddit-selfpost-light.png)

**good** as a component: centred `ContentUnavailableView`, plain-language title, a description that names the host, a prominent "Try Again" and a secondary "Open in Safari". This is the best error state in the app.

**inconsistent** in context: the pink player bar still offers Play, Tag and Share on an article with no content. The idle bar isn't state-aware.

Also note the nav subtitle here is `www.reddit.com` — a third host format alongside `overreacted.io` and `YouTube`, and the app already has a `www.`-stripping helper (`signInHost`) that this path doesn't use.

### Reader — highlighting

| Selection creates instantly | Edit menu | Colour menu | Edit sheet |
|---|---|---|---|
| ![Instant highlight](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/20-reader-chrome-legibility-light.png) | ![Edit menu](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/21-highlight-editmenu-light.png) | ![Colour menu](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/22-highlight-colormenu-light.png) | ![Edit sheet](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/23-highlight-editsheet-light.png) |

**good.** Highlight rendering itself is excellent — the composited paint sits under the text without hurting legibility in either scheme, and instant-on-selection is a confident, Readwise-correct choice. The edit menu's verbs ("Color", "Add Note", "Remove Highlight") are clear and correctly destructive-tinted.

**inconsistent.**
- Two colour pickers (theme 7).
- The edit sheet **never shows the quoted text you are editing**. You are choosing a colour and writing a note about a passage you cannot see.
- The `.medium` sheet sits over a blurred article, and the pink capsule bleeds through as a large pink smear directly behind the red "Remove Highlight" row.
- "Remove Highlight" is a full-width row inside a rounded container identical to the Note text field above it, so a destructive action and a text input share a shape.

### Reader — TTS playing

![TTS playing](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/25-reader-tts-playing-light.png)

**good.** The silk-ribbon waveform is real craft: layered sine motion with an envelope so it never looks periodic, and the played fraction rendered at full brightness so the ribbon doubles as a progress readout. The transport cluster is clear, the speed cycler is a nice compression of a picker into one tap.

**inconsistent.**
- The spoken-paragraph tint collides with yellow highlights (theme 7).
- The capsule changes width dramatically between idle (hugs content, ~340pt) and playing (full width) because the waveform takes `maxWidth: .infinity`. The intent is "one reshaping object" but the read is a jump between two different objects.
- Still occludes body text (theme 3).

### Reader — typography sheet

| | |
|---|---|
| ![Typography 1](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/13-typography-sheet-light.png) | ![Typography 2](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/14-typography-sheet-2-light.png) |

**good** — the strongest non-reading surface in the app. Theme swatches show real paper colour with real ink colour and a live "Aa". Font rows render each family in its own typeface. Eleven curated faces grouped Reading / Accessibility / Sans, including bundled Atkinson Hyperlegible and Lexend. This is the one place where a design decision was clearly made and executed.

**inconsistent.**
- **Two slider treatments in one sheet.** Size has min/max `A`/`A` value labels *and* a "18 pt" row beneath; Line Spacing and Paragraph Spacing have bare sliders with a "6 pt" / "12 pt" row beneath.
- The pt value gets its own full list row instead of trailing the control, costing a row of height each and reading as a stray label.
- Four related controls (Size, Line Spacing, Paragraph Spacing, Width) get four separate grouped sections with four headers. Heavy chrome for one idea.
- Header capitalisation mixes: "Line Spacing" / "Read Aloud" (title case) against "Light theme" / "Dark theme" (sentence case) in the same sheet.
- Selection is a ring here, a checkmark-in-swatch in the highlight sheet, blue-text-plus-check in Tags.
- Full-height with no detent, so you cannot see the article while tuning its typography — which is the entire purpose of the sheet.
- Read Aloud (Provider/Voice) is duplicated verbatim from Settings.

### Reader — tag sheet

![Tag sheet](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/24-tag-sheet-light.png)

**inconsistent.** Full-height for one input row and a short list, with no empty state at all — before you add a tag it is a title, a field, and void. Tags render as blue text rows with a blue checkmark, not as pills, despite capsules being the app's established shape for exactly this kind of token (unread badge, status pill, player). Input is silently title-cased ("react" → "React") with no indication.

### Highlights tab

![Highlights](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/26-highlights-populated-light.png)

**inconsistent**, and the weakest full surface in the app.
- **Rows are not tappable.** There is no link back to the passage in the article. The core loop of a Readwise-style app — revisit a highlight, jump to its context — does not exist.
- **No grouping by article.** Two highlights from one article print the full article title twice.
- **Hierarchy is inverted.** The source title is the top line at full width; the quote — the actual content — sits below it at similar visual weight. The metadata leads.
- Colour reduced to an 8pt dot.
- No date, no tag, no filter, no sort, no search.
- Article titles carry the un-stripped site suffix.
- Grouped list style, unlike its sibling tabs (theme 1).

**Empty state — fine.** ![Highlights empty](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/03-highlights-empty-light.png) Boxed in a card at the top rather than centred, a third placement for `ContentUnavailableView`.

### Search

| Empty | Results |
|---|---|
| ![Search empty](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/04-search-empty-light.png) | ![Search results](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/27-search-results-light.png) |

**Empty — good.** Correctly centred (via `.overlay`), which is what Library and Feeds should copy.

**Results — inconsistent.**
- **No match context.** A body-text hit shows no snippet, so you cannot tell why a result matched.
- The prompt says "Search articles and highlights"; the implementation searches `title`, `plainText` and `author` only. Highlights are never searched. The copy promises a feature that isn't there.
- The query is auto-capitalised ("render" → "Render") — `.searchable` lacks the `.textInputAutocapitalization(.never)` that the URL fields all have.
- The same `ArticleRow` gets a disclosure chevron here (real `NavigationLink`) and none in Library (hidden link in a `ZStack`).
- Read articles render `.secondary`, so in a one-result list the single result looks disabled.

### Settings

| Top | Reader / Experiments / Reddit |
|---|---|
| ![Settings 1](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/28-settings-1-light.png) | ![Settings 2](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/29-settings-2-light.png) |

**inconsistent.**
- **No dismiss control.** Presented as a sheet with no Done button; swipe is the only exit.
- **Three icon treatments in the first three sections**: monochrome grey cloud (iCloud), tinted blue person-key (Site Logins), no icons at all (Read Aloud).
- **`Settings > Reader` duplicates a strict subset of the Typography sheet** — Appearance and Font Size only, omitting family, line spacing, paragraph spacing, width and the theme swatches — with no cross-link between them. And Font Size is designed *differently* in the two places: `Font Size: 18 pt` label-above-slider here, `Size` section with `A`/`A` labels and a separate pt row there.
- **Read Aloud is duplicated verbatim** in Settings and Typography.
- "Block reader (beta)" is **on by default**, and lives in `Reader` while "Sidebar navigation (experiment)" lives in `Experiments` — two words for the same status, two homes.
- Developer-facing copy in a user surface: "iCloud sync not enabled in this build".
- Disabled "Save Key" renders as grey text visually identical to the placeholder above it; worse in dark mode.
- The Reddit section header sits above a single unrelated picker, because the Reddit Account row is hidden when no client ID is configured (as in this build).

**Dark — fine.** ![Settings dark](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/38-settings-1-dark.png)

### Site Logins

![Site Logins](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/30-sitelogins-empty-light.png)

**good.** The best empty state in the app: properly centred, and the description explains the mechanism that would populate it ("When you sign in to a member-only article from its reader banner, that site shows up here…") rather than just naming the void. This is the template the other empty states should follow.

### Import Subscriptions

![Import](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/31-youtube-import-light.png)

**jarring** (minor but very visible). Because each option is a `Button`, the tint cascades and **both the title and the descriptive subtitle render in blue**. Explanatory copy is painted as if it were interactive. Also: two related choices are split into two single-row sections, creating a large gap between them; and "Close" is the fourth dismissal verb in the app.

### Sidebar experiment

| Closed | Open |
|---|---|
| ![Sidebar closed](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/34-sidebar-closed-light.png) | ![Sidebar open](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/36-sidebar-open-light.png) |

**good** on information architecture — and this is the most important finding in the audit.

The sidebar does what the shipping Feeds tab does not:
- **Groups subscriptions by source kind** (YouTube / Reddit / Websites) with brand-coloured group icons.
- **Gives every feed a source identity** via a coloured monogram avatar (V / A / D).
- Surfaces counts at every level, and puts Library, All Items, Highlights, Search and Settings in one place.
- Has a real header: "Read Later · 3 subscriptions · 86 unread".

The experiment behind a flag has better IA and a better visual system than the default. That is a design-language decision, not a fix.

**inconsistent** in execution:
- **Separator insets are chaotic** — at least four different left insets within one list (Library and All Items at ~134, group rows at ~113, feed rows at ~181, Highlights/Search/Settings at ~134). The ragged stack of rule start-points is very visible.
- Only the selected top-level row has a selection style (blue fill); groups and feeds have none.
- The trigger is a thin blue-outlined circle with blue hamburger lines at bottom-left — a button style used nowhere else, and weak on a black background in dark mode.
- Group icons mix fidelity: real YouTube brand mark, generic orange speech bubbles for Reddit, system blue globe for Websites.

**Dark — fine.** ![Sidebar dark](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/37-sidebar-closed-dark.png)

### Add sheets

| Add Feed | Add URL |
|---|---|
| ![Add Feed](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/06-addfeed-sheet-light.png) | ![Add URL](https://raw.githubusercontent.com/elliebartling/read-later/claude/design-audit/audit/15-addurl-sheet-light.png) |

**inconsistent.** Near-identical sheets with different titles ("Add Feed" / "Add URL"), different confirm verbs ("Subscribe" / "Save"), and different error handling — Add Feed has an inline error row, Add URL has none and accepts anything `URL(string:)` parses. Both waste a full-height sheet on one field.

---

## Button vocabulary inventory

Counted across the app, for the design-language doc to collapse:

1. **Glass circle** — nav bar back / gear / plus / mark-all-read
2. **Glass pill containing two glyphs** — reader trailing toolbar (video + AA)
3. **Saturated pink capsule** — reader idle and playing player bars
4. **Thin blue-outlined circle** — sidebar trigger
5. **Filled blue circle** — sidebar header `+`
6. **Plain tinted text** — "Export All Articles", "Save Key", "Add" in the tag sheet
7. **Filled prominent capsule / bordered capsule** — failed-parse "Try Again" / "Open in Safari"

Seven, for an app with four tabs.

---

## Not captured

| Surface | Why |
|---|---|
| **Paywall / member-only banner** | Needs an article that trips `isPaywalledPartial`. None of the seeded sources produced one. The code path (`paywallBanner` → `SiteLoginView` → re-extract) is present and reviewed; the banner reuses the neutral `statusPill`, which is correctly distinct from the pink player capsule. |
| **Site-login sheet chrome** | Only reachable from the paywall banner above. |
| **Reddit sign-in / saved-post picker** | `RedditAuthConfig.clientID` is unconfigured in this build, so `reddit.isConfigured` is false and the entire account row is hidden. Not reachable without credentials. |
| **Re-extract spinner / success toast** | Transient (2.5 s); did not land in a capture. The neutral `statusPill` styling is shared with the paywall banner. |
| **Share extension UI** | Requires driving Safari's share sheet; out of scope for this pass. |

---

## If we fix only ten things

Ordered by ratio of perceived-quality gain to effort.

1. **Give the reader chrome a real material in light mode, and inset content beneath both bars.** Article text currently renders through the nav bar and under the player. This is the single most visible defect and it is a two-property fix. *(theme 3)*
2. **Pick one page surface and delete the ad-hoc `listStyle`s.** Highlights stops being a different app from Feeds. One line per file. *(theme 1)*
3. **Fix the "Saved" badge wrap.** `lineLimit(1)` + `fixedSize` stops "Save"/"d" rendering across two lines and un-truncates the feed name. *(Feed entries)*
4. **Fix list hanging indents in the block reader.** Wrapped list items currently align under the bullet. Highest-value single typography fix. *(Block reader)*
5. **Delete the text-only colour picker; use the swatch row everywhere.** One component, and the app's core taxonomy finally shows its colour. *(theme 7)*
6. **Give the spoken-paragraph tint its own colour.** Reading position must not look like a yellow highlight. *(theme 7)*
7. **Make Highlights rows tap through to the passage, and group them by article.** Turns a dead list into the feature the app is named around. *(Highlights)*
8. **Wire reading-position restore into the block reader.** The state is already persisted and already ignored; the default reader silently lost a shipped feature. *(theme 5)*
9. **Unify the two list rows: one metadata grammar, one unread signal, one source format.** Pick icons-or-interpuncts, decide whether Library gets thumbnails, and normalise `siteName ?? host`. *(theme 4)*
10. **Strip the transcript timestamps and the RSS boilerplate.** `0:1212 seconds` and `submitted by /u/X [link] [comments]` are the two pieces of visible garbage a new user meets first. *(theme 8)*

**And one decision that isn't a fix:** resolve the sidebar experiment. It has the source identity, the grouping and the header the shipping navigation lacks. Either promote it and delete the tab bar, or port its IA into the Feeds tab. Leaving the better design behind a flag is the most expensive thing in this list.

---

## What's already good

Worth protecting through the pretty pass:

- **Reader body typography.** Face, size, leading, paragraph spacing and measure are all correct and clearly deliberate. The dark reader in particular is excellent.
- **The theme system.** Eight palettes with hand-tuned ink/paper pairs, split cleanly into light and dark sets, with a live swatch picker that shows real colour. Better than most shipping readers.
- **The font catalogue.** Eleven faces, grouped by purpose, each row rendered in its own typeface, with bundled OFL accessibility faces and a graceful fallback if registration fails.
- **Highlight paint.** The multiply-on-light / screen-on-dark composite keeps text legible on all eight papers. Subtle and correct.
- **The TTS waveform.** Genuine craft, and it does double duty as a progress readout.
- **The failed-parse state and the Site Logins empty state.** Both are well-composed, plain-spoken, and offer a way forward. Use them as templates.
- **The sidebar's information architecture.** Source-kind grouping with per-feed identity is the right model for a three-source reader.
