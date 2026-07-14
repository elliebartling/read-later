# Parser cruft removal — design

Status: **approved by Ellen (2026-07-13)** — her four review decisions are
recorded under "Review decisions" below and implemented on this branch.
Owner file set: `ReadLater/Services/ArticleParser.swift`, its JS wrapper, and the
new `ReadLater/Services/Parsing/` sources. Does **not** touch any Blocks/ view.

## Problem

Readability.js extracts a readable body, but a meaningful slice of what it keeps
is not article content — it is site chrome that lives *inside* the extracted
region and therefore survives Readability's own cleanup. Concrete examples Ellen
hit on Medium in one evening:

- "Get [Author]'s stories in your inbox"
- "Join Medium for free to get updates from this writer."
- "Remember me for faster sign in"

…plus the generic family: social follow/share rows, "N min read" byline
metadata, login/signup nags, and newsletter subscribe prompts.

This cruft pollutes three things at once: the reader view, the **highlight
offset space** (`plainText`), and TTS (it gets read aloud).

## Non-negotiable constraint: highlight offsets

`plainText` is the UTF-16 offset space for every stored highlight. Stripping
cruft shortens `plainText` and shifts every offset after the removed run.
**Re-filtering an already-saved article would silently misplace its
highlights.** The `quotedText` fallback search can re-anchor some, but it is a
safety net, not a plan.

Therefore filtering is applied **only when an article is (re)parsed**:

- **First ingest** (`PendingSaveIngest.parseOne`) — the article has no highlights
  yet, so there is nothing to shift.
- **Explicit Re-extract** (`ReaderView.reextract`) — user-initiated; highlights
  already re-anchor lazily via the `quotedText` fallback on next render, and the
  user asked for a fresh extraction.

Already-saved articles are **never** re-filtered in the background. Their stored
`plainText` / `blocksJSON` are untouched until the user re-extracts. See "Version
stamp" below for why we deliberately did **not** bump `blocksVersion`.

## Taxonomy of cruft

Two axes: how site-specific the signal is, and how it is shaped in the DOM.

### 1. Named-vendor nags (high confidence, phrase-driven)

Stable marketing copy from big platforms. Matched by curated phrases:

| Vendor    | Example copy                                             |
|-----------|---------------------------------------------------------|
| Medium    | "Join Medium for free…", "…stories in your inbox", "Member-only story" |
| Substack  | "Subscribe to …", "Type your email…", "get updates from this writer" |
| Generic   | "Sign up for our newsletter", "Become a member", "Create a free account" |

### 2. Auth CTAs (high confidence, exact short blocks)

Whole-block, ≤ ~6 words, exact match: "Sign in", "Sign up", "Log in",
"Continue with Google/Apple/Facebook/Email", "Remember me for faster sign in".
A real sentence that merely *contains* "sign in" ("You'll need to sign in to
your bank first.") is long, so it never matches.

### 3. Social follow/share clusters (medium confidence, cluster-gated)

Single-word or short social CTAs: "Share", "Tweet", "Follow", "LinkedIn",
"Reddit", "Copy link", "Share on Twitter"… These are dangerous in isolation (a
one-word "Share." *could* be prose), so a social CTA is only removed when it is
**clustered** — it is a list item, or an adjacent block is also a social/auth
CTA. A lone social word in running prose survives.

### 4. Reading-time / listen metadata (high confidence, regex)

Whole-block regex: `^\d+\s*min(ute)?s?\s*(read|listen)$`, and "N free stories
left" counters.

### Anti-taxonomy (must survive — counter-fixtures)

- Short paragraphs that merely contain links.
- A real "sign in" **sentence** inside article prose.
- A tutorial heading like "Sign in" (headings are exempt from the exact
  auth/social rules; only phrase + regex rules touch headings).
- Legitimately short paragraphs ("Yes.", "It worked.").

## Where to strip: two conservative layers

We use a **DOM-level pre-Readability pass + a block-level post-filter**, each
doing what it is best at.

### Layer A — DOM pre-Readability (minimal, structural)

In the JS wrapper, on the *cloned* document, before `new Readability`, remove
overlay chrome that is unambiguously not article content:
`[role="dialog"]`, `[role="alertdialog"]`, `[aria-modal="true"]`. These are
sign-in / subscribe modals. This layer is intentionally tiny and high-precision
because JS DOM removal is the hardest to unit-test and the easiest to get wrong
(a too-broad class selector eats real sections). Expanding it should be done
cautiously and paired with fixtures.

### Layer B — block-level post-filter (the workhorse, pure + tested)

After `ArticleParser.blocks(fromJS:)` produces typed `[ArticleBlock]` (post
preformatted-coalescing), run `CruftFilter.filter(_:)` — a **pure, nonisolated**
function driven by rule tables in `CruftRules.swift`. Because it operates on
already-normalized block text, it is trivially unit-testable with block-array
fixtures (no WKWebView). `plainText` is then derived from the filtered blocks
(existing code path), so text and blocks stay byte-consistent.

### Composition with the quality gate (`gateAndFilter`)

The parser's retry loop (render pump → extract → `QualityGate`) evaluates the
gate against the **post-filter** article, so cruft removal and the nav-shell
gate compose: a page that is mostly chrome still fails the gate after the
chrome is stripped. One interaction is handled explicitly in
`ArticleParser.gateAndFilter` (pure, unit-tested): if the *filtered* result
fails the gate but the *unfiltered* one would pass — i.e. cruft removal alone
pushed a borderline-short legit article below the gate's 50-word floor — the
filter backs off entirely and the article is kept with its cruft. Keeping a nag
on screen beats rejecting a real article as `.lowQuality`.

Conservative guards baked into Layer B:

- Length-gated: phrase rules only fire on blocks ≤ 25 words; auth-exact ≤ 6
  words; social/exact require a whole-block match after punctuation stripping.
- Cluster-gated social removal (above).
- Headings exempt from exact auth/social rules.
- Never removes the last remaining content block (guard against nuking a
  pathologically short article to empty).

## Version stamp — why `blocksVersion` stays at 1

`blocksVersion` is documented in-code as a **schema** version, and
`DecodedBlocksCache` explicitly relies on re-extract *not* bumping it. Nothing in
the app reparses on a version mismatch, so bumping it would neither trigger
re-filtering nor change behavior — it would only muddy the schema-version
meaning and break a test asserting `== 1`. Offset safety already comes from
"filter only at parse time," not from a version gate. The "was filtered" signal
Ellen asked for is the **separate** `wasCruftFiltered` field (below), not an
overload of `blocksVersion`.

## Review decisions (Ellen, 2026-07-13)

1. **Removed-content persistence — debugging, not UX (yet).** Re-extract is an
   acceptable recovery path while the app isn't live, but what the filter
   removed must stay inspectable. Implemented as two CloudKit-safe fields on
   `Article`: `removedCruftJSON: Data?` (the removed `[ArticleBlock]`, encoded;
   nil when nothing was removed; decoded via `removedCruftBlocks`) and the flag
   below. Both are overwritten on every parse so they always describe the
   *current* `plainText`/blocks.
2. **"Was cruft-filtered" field — yes.** `wasCruftFiltered: Bool = false`
   (inline default, CloudKit-safe). Debug signal short-term.
3. **Rule aggressiveness — keep conservative.** The current tables stand; no
   expansion until real-world misses drive specific additions.
4. **Legacy fallback text pass — skipped.** Articles whose parse yields no
   typed blocks keep unfiltered legacy text (see Deferred).

## Deferred / future work

- **"Show removed content" escape hatch (UI)**: the storage side now exists
  (`removedCruftJSON`); the reader-side reveal is a view change owned by
  another agent and stays out of scope for this cut.
- Substack/Medium DOM selector expansion (Layer A growth) with fixtures.
- Locale/i18n: rule tables are English-only today.
- A library-wide "re-extract all" migration once the escape hatch exists.
- **Text-level filtering for the no-blocks legacy fallback path** — explicitly
  skipped per review decision 4; that path passes `legacyText` through
  `gateAndFilter` unfiltered.

## Test strategy

Fixture-driven, pure, fast (no WKWebView):

- **Removal fixtures**: one per cruft family (Medium inbox nag, join-Medium,
  remember-me, min-read, social cluster) proving the block is dropped.
- **Counter-fixtures**: link-bearing short paragraph, real "sign in" sentence,
  tutorial "Sign in" heading, isolated social word — all proving survival.
- **Offset-parity**: `derivePlainText` over filtered blocks equals the expected
  post-filter join, confirming the offset space is what the reader sees.
- **Gate composition**: `gateAndFilter` fixtures — long article with a nag
  (filter fires, gate passes), borderline 51-word article whose nag removal
  would fail the 50-word floor (filter backs off), nav shell (still rejected),
  and the empty-blocks legacy path (text passes through unfiltered).
- **Debug persistence**: `Article.apply` records `wasCruftFiltered` +
  `removedCruftJSON` and clears them on a later clean parse.
