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

    /// End-to-end: a member-only preview whose schema.org JSON-LD ships
    /// `isAccessibleForFree:false` still parses (the preview is real prose that
    /// clears the gate) but is flagged partial — the exact shape of the reported
    /// Medium article.
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
        XCTAssertTrue(parsed.isPaywalledPartial, "schema.org isAccessibleForFree:false should flag the article")
        XCTAssertFalse(parsed.plainText.isEmpty, "the free preview prose should still be saved")
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
}
