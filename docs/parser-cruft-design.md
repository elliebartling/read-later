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

### 5. Label/value metadata stacks (round 2 — press-release furniture)

TestFlight evidence (ScienceDaily / university press releases): a structured
header stack extracts as separate paragraphs — "Date:", "July 14, 2026",
"Source:", "University of Michigan", "Summary:" — plus footer furniture
("Story Source:", "Journal Reference:", "Cite This Page:", "FULL STORY",
"RELATED STORIES/TERMS/TOPICS"). Verified against a live ScienceDaily page
(2026-07-14). Rules:

- **Field labels** ("Date:", "Source:", "Updated:"…): whole-block match, ≤ 4
  words, and the RAW text must end with ":". Removal also consumes the
  immediately-following block when it reads as a VALUE — ≤ 8 words and
  non-sentential (no interior ". ", no terminal ./!/?). A long or
  sentence-like follower survives; only the label falls.
- **Label-only** ("Summary:", "Story Source:", "Journal Reference:", "Cite
  This Page:"): the label falls alone. **The "Summary:" decision:**
  ScienceDaily's summary value duplicates the article abstract — real prose
  the user may want to read, highlight, and hear in TTS — so we keep the
  value and drop only the label. "Story Source:"'s boilerplate value falls to
  new phrase rules ("materials provided by", "content may be edited for style
  and length"); **journal citations are deliberately kept** (scholarly value,
  precision over recall).
- **Section furniture** ("FULL STORY", "RELATED STORIES", "Top highlight",
  "Advertisement"…): exact whole-block, colon optional, and — unlike the
  auth/social exact rules — **headings are NOT exempt**, because aggregators
  emit these as headings.
- The trailing-colon requirement on the raw text is the precision anchor: a
  legit colon-less "Summary" section heading, or "Date:" used mid-sentence,
  can never match.

### 6. Engagement counters (round 2 — Medium clap stacks, cluster+tail-gated)

TestFlight evidence (Medium, post-content zone): standalone paragraphs
"3.6K", "2", "Top highlight", "1", "1", "1", "1" — clap counts, response
counts, highlight-engagement furniture. Bare numbers are the most dangerous
pattern in the whole taxonomy (a listicle paragraph that is just "42" is real
content), so the gates are the strictest:

- Candidate: whole-block bare number (`^\d{1,4}(,\d{3})*$`) or K/M/B count
  (`^\d+(\.\d+)?[kmb]$`), **paragraphs only** — numeric list items (lottery
  numbers, tabular data) and numeric listicle headings ("1.") are exempt.
- Removed only when **clustered**: adjacent to non-counter cruft anywhere, or
  adjacent to any cruft when the block sits within the last 12 blocks of the
  article (the tail zone). A lone "42" survives everywhere; a mid-article
  "3" / "2" / "1" countdown is a pure-counter run outside the tail and
  survives; the end-of-article clap stack dies.
- Counts with the unit attached ("47 responses", "3.6K claps") are
  unambiguous and fall to whole-block metadata regexes unconditionally.

### Anti-taxonomy (must survive — counter-fixtures)

- Short paragraphs that merely contain links.
- A real "sign in" **sentence** inside article prose.
- A tutorial heading like "Sign in" (headings are exempt from the exact
  auth/social rules; only phrase + regex + label/furniture rules touch
  headings).
- Legitimately short paragraphs ("Yes.", "It worked.").
- Round 2: "Date:" used inside prose; a colon-less "Summary" heading;
  definition-list content ("Ingredients:" / "Flour, sugar, and butter");
  a lone "42" listicle paragraph (even in the tail); a mid-article countdown
  run; bare-number list items; numeric listicle headings.

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

## The long tail: on-device model classification (FoundationModels)

Deterministic rules will never enumerate every site's furniture — round 2
exists because ScienceDaily and Medium each shipped patterns round 1 didn't
know. Ellen asked for a design for using Apple's on-device LLM as the cruft
long-tail classifier. Researched against current API reality (July 2026);
**not implemented yet** — this section is the plan.

### The framework, verified

`FoundationModels` (iOS 26+) exposes the ~3B-parameter Apple Intelligence
on-device LLM. Key facts that shape this design:

- **Availability is a runtime question, not just an OS check.**
  `SystemLanguageModel.default.availability` returns `.available` or
  `.unavailable(reason:)` — reasons include device not eligible (no Apple
  Intelligence hardware), Apple Intelligence disabled in Settings, and model
  not ready (still downloading). The app must treat the model as a bonus
  layer that can vanish; deterministic rules remain the floor. Our deployment
  target is already iOS 26.0, so no `#available` gate is needed — only the
  availability check.
- **Context window is a hard 4,096 tokens per `LanguageModelSession`**
  (prompt + output combined; exceeding it throws
  `exceededContextWindowSize`). A full article does not fit and must never be
  sent whole.
- **Guided generation via `@Generable`** constrains decoding to a
  compiler-derived schema — the model *cannot* return malformed output. This
  is the right shape for classification: a `@Generable struct` of
  per-block verdicts, not free text.
- **Latency**: on the order of ~1s per short request on current hardware;
  fine for a background parse pipeline, unacceptable for anything
  interactive. Energy cost is nonzero — another reason to send as little as
  possible.

### Where it slots: the ambiguous middle tier only

The pipeline stays rules-first. The model never sees whole articles and never
overrides the safety rails:

1. **Deterministic rules run first** (Layers A + B as shipped). High-confidence
   removals happen without the model.
2. **Candidate selection**: only *ambiguous* blocks go to the model — short
   blocks (≤ ~25 words) in the article's head/tail zones that triggered a
   near-miss signal (counter candidate outside its gate, social candidate
   without a cluster, label-shaped block not in the tables, link-dense short
   block). A ~100-block article typically yields **5–15 candidates**, batched
   into ONE request with a few words of neighbor context each — comfortably
   inside 4,096 tokens. Never the whole article.
3. **Verdicts apply only as removals of candidates** — the model can confirm
   a suspicion, never invent one about a block the rules considered clean.
   Blocks the model calls content stay, blocks it calls cruft are removed
   *through the same pipeline* (recorded in `removedCruftJSON`,
   `wasCruftFiltered`).
4. **The zero-content backoff and `gateAndFilter` gate-composition run AFTER
   model filtering, unchanged.** The model can never nuke an article or push
   one below the quality gate — the same backoff that protects the rules
   protects it.
5. On `.unavailable(...)`: skip step 2–3 silently. Identical behavior to
   today; no UI, no error.

### Prompt + output shape (sketch)

```swift
@Generable
struct BlockVerdicts {
    @Generable
    struct Verdict {
        @Guide(description: "Index of the block being classified")
        var index: Int
        @Guide(description: "true only when the block is site furniture — subscribe/sign-in prompts, share rows, engagement counts, metadata labels — and NOT article prose")
        var isCruft: Bool
    }
    var verdicts: [Verdict]
}
```

Session per parse (Apple's guidance: fresh session per single-turn task), with
`instructions` framing the task ("You classify reader-view text blocks as
article content or site furniture. When unsure, answer content.") — the
"unsure → content" instruction encodes precision-over-recall in the prompt
itself. Prompt lists numbered candidate blocks with one-line neighbor context.

### Privacy story

Everything stays on-device: the FoundationModels runtime never sends text to
Apple or anyone else, which means article text — potentially paywalled,
member-only, or personal — never leaves the phone. This is materially better
than any server LLM and is the reason to prefer FoundationModels over an
OpenAI call even though we already have an OpenAI key for TTS. No new privacy
disclosures needed.

### Testing nondeterministic output

- **The seam is deterministic**: candidate selection and verdict application
  are pure functions — unit-test them with a scripted `CruftAdvisor` protocol
  fake (verdicts injected), exactly like `TTSControllerTests` fakes its
  engine. The model conforms to the protocol in production.
- **Live-model tests** exist but only as a manually-run, device-only XCTest
  marked skipped in CI (CI simulators have no Apple Intelligence): a small
  golden set of cruft/content blocks asserting directional accuracy (e.g.
  ≥ 90% on the golden set), tolerating individual flips.
- **Property invariants** hold regardless of model output: never removes a
  non-candidate, never empties an article, never moves a block, offsets
  derived post-filter as always.

### v1 recommendation + effort

Ship the middle tier as a Settings-gated experiment ("Smart cruft removal
(beta)", default OFF initially) in this order: `CruftAdvisor` protocol +
candidate selection + verdict application with fakes (~1 day), the
FoundationModels adapter with availability gating (~0.5 day), golden-set
device test + prompt tuning (~0.5–1 day of iteration on real saves). **Total:
roughly 2–3 focused days**, no schema changes (reuses `removedCruftJSON`),
fully removable. Prerequisite: none — the seam (`CruftFilter.Result`,
`gateAndFilter`) already exists. Recommend building it after one more round
of deterministic-rule feedback, so the model tier launches against a known
residue rather than cruft the tables should have caught.

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
- **Round 2**: ScienceDaily header stack (distilled from a live page),
  story-source boilerplate, citation-labels-fall-citation-stays, share row as
  a single block, Medium engagement stack — plus the round-2 anti-taxonomy
  counter-fixtures listed above.
