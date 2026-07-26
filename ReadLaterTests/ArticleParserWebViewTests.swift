import XCTest
@testable import ReadLater

/// End-to-end parser tests that drive the real WKWebView + bundled
/// Readability.js via `prefetchedHTML` (no network). These validate the pieces
/// that only exist in the injected JS — code-block classification — plus the
/// stabilization → gate → retry loop rejecting a nav shell. The test target is
/// hosted by the app (`TEST_HOST`), so WKWebView is fully available.
@MainActor
final class ArticleParserWebViewTests: XCTestCase {

    private let url = URL(string: "https://example.com/article")!

    private func page(body: String) -> String {
        "<!doctype html><html><head><title>Fixture</title></head><body>\(body)</body></html>"
    }

    /// A few sentences so Readability accepts the document and the quality gate
    /// clears its word floor.
    private let prose = """
    <p>This walkthrough explains how to get the command line tools installed on a
    fresh machine without any prior setup. The process is short but it helps to
    read the whole thing first so nothing surprises you along the way.</p>
    <p>Everything below has been tested on a clean install, and each step is
    independent enough that you can stop and resume later if you need to step
    away from your desk for a while.</p>
    """

    func testMultiLinePreBlockCoalescesIntoOneCodeBlock() async throws {
        // Medium's classic pattern: each code line is its own <pre> sibling.
        let body = page(body: """
        <article>
        <h1>Setting up the CLI</h1>
        \(prose)
        <p>Run these three commands in order:</p>
        <pre>brew tap example/tap</pre>
        <pre>brew install example</pre>
        <pre>claude mcp add-json '{"name":"example"}'</pre>
        <p>That is all it takes to get a working installation on your machine.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        let pres = parsed.blocks.filter { $0.type == .preformatted }
        XCTAssertEqual(pres.count, 1, "per-line <pre> siblings should coalesce into a single code block")
        let code = pres.first?.text ?? ""
        XCTAssertTrue(code.contains("brew tap example/tap"), "code: \(code)")
        XCTAssertTrue(code.contains("brew install example"), "code: \(code)")
        XCTAssertTrue(code.contains("claude mcp add-json"), "code: \(code)")
        XCTAssertTrue(code.contains("\n"), "coalesced code block must preserve line breaks; got: \(code)")
    }

    func testCodeOnlyParagraphsCoalesceIntoOneCodeBlock() async throws {
        // Medium also marks code lines as <p><code>…</code></p>.
        let body = page(body: """
        <article>
        <h1>Config</h1>
        \(prose)
        <p>Add the following to your shell profile so the tool is always on PATH:</p>
        <p><code>export PATH="$HOME/bin:$PATH"</code></p>
        <p><code>export EXAMPLE_TOKEN=abc123</code></p>
        <p>Reload the shell and you are ready to go with the new configuration.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        let pres = parsed.blocks.filter { $0.type == .preformatted }
        XCTAssertEqual(pres.count, 1, "code-only <p> siblings should classify as one coalesced code block")
        let code = pres.first?.text ?? ""
        XCTAssertTrue(code.contains("export PATH="), "code: \(code)")
        XCTAssertTrue(code.contains("export EXAMPLE_TOKEN="), "code: \(code)")
        XCTAssertTrue(code.contains("\n"), "code: \(code)")
        // Regression guard: the code lines must NOT leak into a paragraph block.
        XCTAssertFalse(
            parsed.blocks.contains { $0.type == .paragraph && ($0.text ?? "").contains("export PATH=") },
            "code line was misclassified as body text"
        )
    }

    func testNavShellIsRejectedByQualityGate() async {
        // The failure Ellen hit: WKWebView captured only the app shell.
        let body = page(body: """
        <nav><a href="/sitemap">Sitemap</a> <a href="/signin">Sign in</a>
        <a href="/write">Write</a> <a href="/search">Search</a></nav>
        """)

        do {
            _ = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
            XCTFail("nav-shell page should not produce a saved article")
        } catch {
            // Expected: gate rejected every attempt (or Readability found no
            // article). Either way the caller records `.failed` and can retry.
            XCTAssertTrue(error is ArticleParser.ParseError)
        }
    }

    func testRealArticleStillParses() async throws {
        let body = page(body: """
        <article>
        <h1>A normal article</h1>
        \(prose)
        <p>Here is a closing paragraph with a little more detail so the extractor
        has plenty of readable prose to work with and comfortably clears the
        content quality gate on the very first pass.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        XCTAssertFalse(parsed.plainText.isEmpty)
        XCTAssertTrue(parsed.blocks.contains { $0.type == .paragraph })
        // A plain article carries no paywall flag.
        XCTAssertFalse(parsed.isPaywalledPartial)
    }

    /// End-to-end: an anonymous member-only preview — schema.org
    /// `isAccessibleForFree:false` and a sub-preview-scale capture — still
    /// parses (the preview is real prose that clears the gate) but is flagged
    /// partial. The exact shape of the reported Medium article.
    func testPaywalledPreviewParsesButIsFlaggedPartial() async throws {
        let body = page(body: """
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"Article","headline":"Gated","isAccessibleForFree":false}
        ]}
        </script>
        <article>
        <h1>A member-only story</h1>
        \(prose)
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        XCTAssertTrue(parsed.isPaywalledPartial,
                      "schema false + preview-scale capture should flag the article")
        XCTAssertFalse(parsed.plainText.isEmpty, "the free preview prose should still be saved")
    }

    /// End-to-end build-31 regression: an *authenticated* fetch of a
    /// member-only article — schema.org still says `isAccessibleForFree:false`
    /// (it always will) but no gate CTA renders and the capture is substantial
    /// — must NOT be flagged partial.
    func testAuthenticatedFullMemberArticleIsNotFlagged() async throws {
        // Enough paragraphs to clear PaywallRules.substantialWordFloor (500
        // words) with margin: ~40 words per paragraph x 16 = ~640 words.
        let longBody = (0 ..< 16).map { i in
            """
            <p>Section \(i) of the complete member article, present because the
            session is authenticated and the wall never rendered on this page.
            Each of these paragraphs carries genuine long-form prose, the kind a
            signed-in reader actually receives, with enough words that the whole
            capture lands comfortably above any preview scale threshold.</p>
            """
        }.joined(separator: "\n")
        let body = page(body: """
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"Article","headline":"Gated but fetched signed-in","isAccessibleForFree":false}
        ]}
        </script>
        <article>
        <h1>A member-only story, fetched with a session</h1>
        \(longBody)
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        XCTAssertFalse(parsed.isPaywalledPartial,
                       "substantial capture with no gate CTA must not be flagged despite schema false")
        XCTAssertTrue(parsed.plainText.contains("Section 15"), "full text should be captured")
    }

    /// End-to-end: a rendered gate CTA flags the capture even when the page
    /// also holds enough prose to look substantial — direct truncation
    /// evidence wins over length.
    func testGateCTAFlagsEvenSubstantialCapture() async throws {
        let longBody = (0 ..< 16).map { i in
            """
            <p>Chunk \(i) of banked pre-gate content with plenty of prose in it,
            long enough that the total capture clears the substantial word floor
            and would otherwise read as a complete article to the heuristic.</p>
            """
        }.joined(separator: "\n")
        let body = page(body: """
        <article>
        <h1>A long capture with the wall still on the page</h1>
        \(longBody)
        <p>Read the full story with a free account.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        XCTAssertTrue(parsed.isPaywalledPartial,
                      "an in-DOM gate CTA is truncation evidence regardless of capture length")
    }

    /// Detection is additive, not a gate: a free article with matching schema
    /// stays unflagged and parses normally.
    func testFreeArticleWithSchemaIsNotFlagged() async throws {
        let body = page(body: """
        <script type="application/ld+json">
        {"@type":"Article","headline":"Open","isAccessibleForFree":true}
        </script>
        <article>
        <h1>An open article</h1>
        \(prose)
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        XCTAssertFalse(parsed.isPaywalledPartial)
        XCTAssertFalse(parsed.plainText.isEmpty)
    }

    /// Simulates a Medium-style lazy renderer: the page initially contains only
    /// the top of the article, and each `scroll` event mounts one more chunk
    /// (the last one carrying an end-of-article marker). Without the render
    /// pump — which scroll-steps the off-screen web view and dispatches
    /// synthetic scroll events until scrollHeight and text length settle at the
    /// bottom — extraction would stabilize on the initial chunk alone and
    /// truncate the article at a consistent point, exactly the bug seen on
    /// device. The marker reaching plainText proves the pump drove the page to
    /// a full render before Readability ran.
    func testLazyRenderedTailIsCapturedByScrollPump() async throws {
        let body = page(body: """
        <article id="story">
        <h1>The lazy article</h1>
        \(prose)
        <p>Everything below this point is mounted lazily by script, one chunk per
        scroll event, exactly like a virtualized reading platform does it.</p>
        </article>
        <script>
        (function() {
            var added = 0;
            var total = 8;
            var filler = "This chunk continues the article with enough prose to move " +
                         "the layout and the rendered text length on every mount so the " +
                         "settle tracker genuinely has to wait for the page to finish. ";
            function mountNext() {
                if (added >= total) { return; }
                added += 1;
                var p = document.createElement("p");
                p.textContent = (added === total)
                    ? "LAZY-TAIL-MARKER this is the true final paragraph of the article."
                    : ("Chunk " + added + ". " + filler + filler);
                document.getElementById("story").appendChild(p);
            }
            window.addEventListener("scroll", mountNext);
            document.addEventListener("scroll", mountNext);
        })();
        </script>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        XCTAssertTrue(
            parsed.plainText.contains("LAZY-TAIL-MARKER"),
            "pump failed to mount the lazy tail; plainText ends with: …\(parsed.plainText.suffix(120))"
        )
        XCTAssertTrue(parsed.plainText.contains("Chunk 4."), "middle chunks missing")
        // The lazy chunks must be part of the block stream too, in order.
        let paragraphTexts = parsed.blocks.compactMap { $0.type == .paragraph ? $0.text : nil }
        XCTAssertTrue(paragraphTexts.contains { $0.contains("LAZY-TAIL-MARKER") })
    }

    /// Simulates a VIRTUALIZING renderer: each scroll event mounts the next
    /// chunk and unmounts everything but the last two — so the full article is
    /// NEVER in the DOM at one instant, and any single final-DOM snapshot is
    /// structurally incapable of containing it. Only the incremental harvester,
    /// which banks blocks as they mount during the pump, can assemble the whole
    /// text. Early chunks reaching plainText proves the banked stream beat the
    /// snapshot; ordering proves the stream preserved document order.
    func testVirtualizedArticleIsAssembledFromHarvestedStream() async throws {
        let body = page(body: """
        <article id="story">
        <h1>The virtualized article</h1>
        \(prose)
        <p>Everything below is mounted lazily one chunk per scroll event, and
        older chunks are unmounted as newer ones arrive, so the document never
        holds the whole story at once.</p>
        </article>
        <script>
        (function() {
            var added = 0;
            var total = 8;
            var live = [];
            var filler = "This chunk carries a decent amount of running prose so that " +
                         "unmounting it visibly shrinks the document and the final " +
                         "snapshot is clearly missing content that already streamed by. ";
            function mountNext() {
                if (added >= total) { return; }
                added += 1;
                var p = document.createElement("p");
                p.textContent = (added === total)
                    ? "VIRT-TAIL-MARKER the story ends here after everything scrolled past."
                    : ("VChunk " + added + ". " + filler + filler);
                document.getElementById("story").appendChild(p);
                live.push(p);
                // Virtualization: keep only the two most recent chunks mounted.
                while (live.length > 2) {
                    var old = live.shift();
                    if (old.parentNode) { old.parentNode.removeChild(old); }
                }
            }
            window.addEventListener("scroll", mountNext);
            document.addEventListener("scroll", mountNext);
        })();
        </script>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        // Early chunks were unmounted long before the final snapshot — they can
        // only come from the harvested stream.
        XCTAssertTrue(
            parsed.plainText.contains("VChunk 1."),
            "harvester failed to bank the virtualized head; plainText starts: \(parsed.plainText.prefix(160))"
        )
        XCTAssertTrue(parsed.plainText.contains("VChunk 5."), "middle chunk missing")
        XCTAssertTrue(parsed.plainText.contains("VIRT-TAIL-MARKER"), "tail missing")
        // Document order must survive the incremental assembly.
        let head = parsed.plainText.range(of: "VChunk 1.")
        let mid = parsed.plainText.range(of: "VChunk 5.")
        let tail = parsed.plainText.range(of: "VIRT-TAIL-MARKER")
        if let head, let mid, let tail {
            XCTAssertTrue(head.lowerBound < mid.lowerBound && mid.lowerBound < tail.lowerBound,
                          "harvested stream lost document order")
        }
    }

    // MARK: - List preservation (bullet/number markers baked into text)

    /// The reported bug: `<ul>`/`<li>` flattened to bare paragraphs. Markers are
    /// now baked into the list item's own text at parse, so they reach the plain
    /// reader (which shows only `derivePlainText`) — and the blocks carry
    /// `markerBaked` so the block reader skips its composed marker.
    func testUnorderedListItemsCarryBulletMarkersInText() async throws {
        let body = page(body: """
        <article>
        <h1>Feature list</h1>
        \(prose)
        <p>The headline capabilities are:</p>
        <ul>
          <li>Offline reading everywhere</li>
          <li>Readwise-style highlighting</li>
          <li>Obsidian export</li>
        </ul>
        <p>Each of those has been battle tested in daily use for months now.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        let items = parsed.blocks.filter { $0.type == .listItem }
        XCTAssertEqual(items.count, 3, "blocks: \(parsed.blocks.map { "\($0.type):\($0.text ?? "")" })")
        for item in items {
            XCTAssertEqual(item.markerBaked, true)
            XCTAssertEqual(item.listStyle, .unordered)
            XCTAssertTrue((item.text ?? "").hasPrefix("\u{2022} "), "missing bullet: \(item.text ?? "")")
        }
        // The marker reaches plainText — this is what fixes the plain reader.
        XCTAssertTrue(parsed.plainText.contains("\u{2022} Offline reading everywhere"),
                      "plainText: \(parsed.plainText)")
        XCTAssertTrue(parsed.plainText.contains("\u{2022} Obsidian export"))
    }

    /// Ordered lists number from the `start` attribute, and each `<li>`'s
    /// ordinal reflects its position among its siblings.
    func testOrderedListRespectsStartAttribute() async throws {
        let body = page(body: """
        <article>
        <h1>Steps</h1>
        \(prose)
        <p>Continue from where the previous section left off:</p>
        <ol start="3">
          <li>Third, install the tap</li>
          <li>Fourth, run the installer</li>
          <li>Fifth, verify the version</li>
        </ol>
        <p>After the final step the tool is ready for everyday use on any machine.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        let items = parsed.blocks.filter { $0.type == .listItem }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.markerBaked), [true, true, true])
        XCTAssertEqual(items.map(\.listStyle), [.ordered, .ordered, .ordered])
        XCTAssertTrue(parsed.plainText.contains("3. Third, install the tap"), "plainText: \(parsed.plainText)")
        XCTAssertTrue(parsed.plainText.contains("4. Fourth, run the installer"))
        XCTAssertTrue(parsed.plainText.contains("5. Fifth, verify the version"))
    }

    /// A nested sublist under a parent item that ALSO carries its own text: the
    /// parent line must not vanish (constraint: never lose content), and the
    /// nested items are indented and independently numbered/bulleted.
    func testNestedListPreservesParentLineAndIndentsChildren() async throws {
        let body = page(body: """
        <article>
        <h1>Outline</h1>
        \(prose)
        <p>The structure looks like this:</p>
        <ul>
          <li>Top level parent item
            <ul>
              <li>Nested child one</li>
              <li>Nested child two</li>
            </ul>
          </li>
          <li>Second top level item</li>
        </ul>
        <p>That covers the full outline that we intend to expand on later.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        // Parent line survives even though it holds a sublist.
        XCTAssertTrue(parsed.plainText.contains("\u{2022} Top level parent item"),
                      "parent list line lost; plainText: \(parsed.plainText)")
        XCTAssertTrue(parsed.plainText.contains("Second top level item"))
        // Children survive and are indented one level (two non-breaking spaces).
        XCTAssertTrue(parsed.plainText.contains("\u{00a0}\u{00a0}\u{2022} Nested child one"),
                      "nested child missing/indent lost; plainText: \(parsed.plainText)")
        XCTAssertTrue(parsed.plainText.contains("\u{00a0}\u{00a0}\u{2022} Nested child two"))
    }

    /// Inline markup inside an `<li>` (links, emphasis) keeps its full text; the
    /// marker prefixes the whole line.
    func testListItemWithInlineMarkupKeepsFullText() async throws {
        let body = page(body: """
        <article>
        <h1>Links</h1>
        \(prose)
        <p>Useful references include:</p>
        <ul>
          <li>The <a href="https://example.com/docs">official docs</a> for setup</li>
          <li>A <strong>very important</strong> note about limits</li>
        </ul>
        <p>Both are worth reading before you begin your first real project.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        XCTAssertTrue(parsed.plainText.contains("\u{2022} The official docs for setup"),
                      "plainText: \(parsed.plainText)")
        XCTAssertTrue(parsed.plainText.contains("\u{2022} A very important note about limits"))
    }

    /// A Reddit self-post shape arrives as prefetched HTML (captured by the
    /// extension) rather than a live fetch: a post-body container with prose and
    /// a `<ul>`. The same walk runs, so its list gets markers too.
    func testRedditSelfPostListGetsMarkers() async throws {
        let body = page(body: """
        <shreddit-post>
          <div slot="text-body" class="md">
            <p>I finally finished migrating my whole reading workflow and wanted to
            share the feature list that made me switch. It took a weekend but it
            was completely worth the effort in the end.</p>
            <p>Here is what sold me on it:</p>
            <ul>
              <li>Highlights sync across all my devices</li>
              <li>Export drops straight into my Obsidian vault</li>
              <li>The reader works fully offline on the subway</li>
            </ul>
            <p>Happy to answer any questions about the setup in the comments below.</p>
          </div>
        </shreddit-post>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        let items = parsed.blocks.filter { $0.type == .listItem }
        XCTAssertEqual(items.count, 3, "blocks: \(parsed.blocks.map { "\($0.type):\($0.text ?? "")" })")
        XCTAssertTrue(items.allSatisfy { $0.markerBaked == true })
        XCTAssertTrue(parsed.plainText.contains("\u{2022} Highlights sync across all my devices"),
                      "plainText: \(parsed.plainText)")
    }

    /// Counter-fixture: ordinary paragraphs must be untouched by list handling —
    /// no stray markers, no reclassification.
    func testNonListParagraphsAreUnchanged() async throws {
        let body = page(body: """
        <article>
        <h1>Plain prose</h1>
        \(prose)
        <p>This paragraph has no list anywhere near it and should be emitted
        exactly as written, with no bullet or number ever prepended to it.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)

        XCTAssertTrue(parsed.blocks.allSatisfy { $0.type != .listItem }, "unexpected list item")
        XCTAssertFalse(parsed.plainText.contains("\u{2022}"), "stray bullet in prose: \(parsed.plainText)")
        XCTAssertTrue(parsed.plainText.contains("no bullet or number ever prepended"))
    }

    // MARK: - Blockquote preservation

    /// Every quoted block, in document order, as (type, text).
    private func quoted(_ parsed: ArticleParser.Parsed) -> [(BlockType, String)] {
        parsed.blocks.filter(\.isQuoted).map { ($0.type, $0.text ?? "") }
    }

    func testSimpleBlockquoteIsFlaggedAndKept() async throws {
        let body = page(body: """
        <article>
        <h1>On simplicity</h1>
        \(prose)
        <blockquote>Everything should be made as simple as possible, but no simpler.</blockquote>
        <p>The point survives every retelling, which is part of why it is quoted so often.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        let q = quoted(parsed)
        XCTAssertEqual(q.count, 1, "blocks: \(parsed.blocks.map { "\($0.type):\($0.text ?? "")" })")
        XCTAssertEqual(q[0].0, .blockquote, "a leaf <blockquote> keeps the legacy type")
        XCTAssertTrue(q[0].1.hasPrefix("Everything should be made as simple"), "got: \(q[0].1)")
        // The quote is part of plainText — the highlight offset space.
        XCTAssertTrue(parsed.plainText.contains("but no simpler"))
    }

    func testMultiParagraphBlockquoteBecomesSeveralFlaggedBlocks() async throws {
        // The bug: <blockquote> wrapping <p>s was not a leaf, so the walker
        // recursed and emitted anonymous paragraphs — the quote was flattened.
        let body = page(body: """
        <article>
        <h1>The interview</h1>
        \(prose)
        <blockquote>
          <p>We tried it the obvious way first and it did not work at all.</p>
          <p>So we started over, and the second attempt is what shipped.</p>
        </blockquote>
        <p>That answer set the tone for the rest of the conversation that afternoon.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        let q = quoted(parsed)
        XCTAssertEqual(q.count, 2, "each quoted paragraph is its own flagged block; got: \(q)")
        XCTAssertTrue(q[0].1.hasPrefix("We tried it the obvious way"), "got: \(q[0].1)")
        XCTAssertTrue(q[1].1.hasPrefix("So we started over"), "got: \(q[1].1)")
        // Regression guard: the quote must not read as ordinary body text.
        XCTAssertFalse(
            parsed.blocks.contains { !$0.isQuoted && ($0.text ?? "").contains("So we started over") },
            "quoted paragraph leaked out as unquoted body text"
        )
        // Ranges derived for the plain reader land on the quote's own text.
        let ranges = ArticleBlocks.quoteRanges(parsed.blocks, in: parsed.plainText)
        XCTAssertEqual(ranges.count, 2)
        let ns = parsed.plainText as NSString
        XCTAssertTrue(ns.substring(with: ranges[0]).hasPrefix("We tried it"))
    }

    func testNestedBlockquoteKeepsAllContent() async throws {
        let body = page(body: """
        <article>
        <h1>Quoting a quote</h1>
        \(prose)
        <blockquote>
          <p>She opened with a line she had clearly used before.</p>
          <blockquote><p>The best time to plant a tree was twenty years ago.</p></blockquote>
          <p>Then she moved on without waiting for anyone to react.</p>
        </blockquote>
        <p>The whole exchange lasted less than a minute from start to finish.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        let q = quoted(parsed)
        XCTAssertEqual(q.count, 3, "no content may be lost to nesting; got: \(q)")
        XCTAssertTrue(q[1].1.contains("plant a tree"), "inner quote text: \(q[1].1)")
        // v1: single-level flagging — the inner quote reads like the outer one.
        XCTAssertTrue(q.allSatisfy { !$0.1.isEmpty })
    }

    func testBlockquoteWithCiteKeepsAttributionAsFlaggedText() async throws {
        let body = page(body: """
        <article>
        <h1>Attribution</h1>
        \(prose)
        <blockquote>
          <p>A language that does not affect the way you think is not worth knowing.</p>
          <cite>Alan Perlis</cite>
        </blockquote>
        <p>The epigram is repeated so often that its source is frequently forgotten.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        let q = quoted(parsed)
        XCTAssertEqual(q.count, 2, "the <cite> attribution must survive; got: \(q)")
        XCTAssertTrue(q[1].1.contains("Alan Perlis"), "attribution: \(q[1].1)")
        XCTAssertTrue(parsed.plainText.contains("Alan Perlis"))
    }

    func testTweetEmbedStyleQuoteKeepsTrailingCreditLine() async throws {
        // Twitter's embed shape: a <p> plus a bare text node and a trailing
        // <a>, all siblings inside the blockquote.
        let body = page(body: """
        <article>
        <h1>What people said</h1>
        \(prose)
        <blockquote class="twitter-tweet">
          <p lang="en" dir="ltr">Shipping is a feature. Your product must have it.</p>
          &mdash; Joel Spolsky (@spolsky)
          <a href="https://twitter.com/spolsky/status/1">March 3, 2019</a>
        </blockquote>
        <p>The line has been repeated in engineering blogs ever since it was posted.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        let q = quoted(parsed)
        XCTAssertGreaterThanOrEqual(q.count, 2, "credit line must survive; got: \(q)")
        XCTAssertTrue(q[0].1.contains("Shipping is a feature"), "quote: \(q[0].1)")
        let credit = q.dropFirst().map(\.1).joined(separator: " ")
        XCTAssertTrue(credit.contains("Joel Spolsky"), "credit line: \(credit)")
        XCTAssertTrue(credit.contains("March 3, 2019"), "credit line: \(credit)")
    }

    func testQuotedListItemsStayListItemsAndKeepMarkers() async throws {
        let body = page(body: """
        <article>
        <h1>Quoted list</h1>
        \(prose)
        <blockquote>
          <p>The charter named three obligations:</p>
          <ul><li>Publish the data</li><li>Answer questions</li><li>Correct mistakes</li></ul>
        </blockquote>
        <p>All three were dropped from the final version that was actually adopted.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        let items = parsed.blocks.filter { $0.type == .listItem }
        XCTAssertEqual(items.count, 3, "quoted list items keep their type")
        XCTAssertTrue(items.allSatisfy(\.isQuoted), "quoted list items are flagged")
        XCTAssertTrue(items.allSatisfy { ($0.text ?? "").hasPrefix("\u{2022} ") },
                      "baked bullet markers survive inside a quote: \(items.map { $0.text ?? "" })")
    }

    func testNormalParagraphsAreNotFlaggedAsQuotes() async throws {
        // Counter-fixture: an article with no <blockquote> must be byte-for-byte
        // what it was before — no block flagged, no quote ranges derived.
        let body = page(body: """
        <article>
        <h1>A normal article</h1>
        \(prose)
        <p>A closing paragraph with enough prose to clear the content quality gate
        on the very first extraction pass without any trouble at all.</p>
        </article>
        """)

        let parsed = try await ArticleParser.shared.parse(url: url, prefetchedHTML: body)
        XCTAssertFalse(parsed.blocks.contains(where: \.isQuoted))
        XCTAssertTrue(parsed.blocks.allSatisfy { $0.isQuote == nil })
        XCTAssertTrue(ArticleBlocks.quoteRanges(parsed.blocks, in: parsed.plainText).isEmpty)
    }
}
