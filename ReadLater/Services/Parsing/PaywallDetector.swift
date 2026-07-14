import Foundation

/// Pure, honest paywall detection for the article pipeline.
///
/// Medium and other metered publishers serve anonymous clients only a preview:
/// the full text never reaches our off-screen WKWebView, so the parser's
/// scroll-pump faithfully captures — and would otherwise save as if complete —
/// a truncated preview.
///
/// The verdict means **"we likely captured a truncated preview"**, NOT "the
/// source is member-only". The distinction matters because the two raw signals
/// carry different evidence:
///
/// 1. **In-DOM gate markers** (`PaywallRules.gatePhrases`) — the
///    register/subscribe calls-to-action a wall renders *in place of* the
///    missing body. Sites only serve these on gated views (signing in removes
///    them), so their presence is direct truncation evidence and flags the
///    capture regardless of anything else.
/// 2. **schema.org `isAccessibleForFree:false`** — describes the article's
///    *public* accessibility and stays false permanently, even when an
///    authenticated fetch (shared cookie jar via `SiteLoginStore`) returned the
///    complete text. Alone it proves the source is metered, not that OUR fetch
///    was truncated — so it flags the capture only when the extracted content
///    is below preview scale (`PaywallRules.substantialWordFloor`).
///
/// Deliberately NOT consulted: cookie presence (`SiteLoginStore` hosts).
/// Anonymous article loads drop persistent cookies for the same registrable
/// domain (the store documents its own list as "cookie soup"), so cookies
/// can't corroborate an authenticated fetch — and an *expired* session
/// re-renders the gate CTAs, which signal 1 already catches.
///
/// Detection is *additive*, never a quality-gate rejection: a member-only
/// preview is real prose and may legitimately pass the gate. We still save what
/// we captured (partial beats nothing) and flag it so the reader can be honest.
///
/// Pure — no WKWebView or main-actor state — so it is unit-testable directly
/// with fixtures. The JS wrapper in `ArticleParser` gathers the raw inputs
/// (JSON-LD blobs + visible body text) and feeds them here.
enum PaywallDetector {

    /// Why a capture was flagged as a truncated preview. Nil `reason` means
    /// not flagged.
    enum Reason: String, Equatable {
        /// schema.org `isAccessibleForFree:false` with sub-preview-scale content.
        case schemaOrg
        /// An in-DOM registration/subscribe gate marker.
        case domMarker
    }

    struct Result: Equatable {
        var isPaywalled: Bool
        var reason: Reason?

        static let free = Result(isPaywalled: false, reason: nil)
    }

    /// The raw per-page signals, split from the verdict so the parser can use
    /// "this source is gated at all" (retry short-circuit on a gate-failing
    /// pass) separately from "this capture is a truncated preview" (the flag
    /// persisted on Article).
    struct Signals: Equatable {
        /// schema.org says the article is not publicly accessible.
        var schemaSaysNotFree: Bool
        /// A gate CTA is rendered in the page — anonymous/gated view.
        var domGateMarker: Bool

        /// The source is metered/gated in some form. On a pass that failed the
        /// quality gate this justifies skipping retries (the body is behind a
        /// login the pump can't defeat).
        var indicatesGatedSource: Bool { schemaSaysNotFree || domGateMarker }

        static let none = Signals(schemaSaysNotFree: false, domGateMarker: false)
    }

    /// Reads both raw signals off the rendered page's JSON-LD and visible text.
    static func signals(jsonLDBlobs: [String], bodyText: String) -> Signals {
        Signals(
            schemaSaysNotFree: jsonLDIndicatesPaywall(jsonLDBlobs),
            domGateMarker: bodyIndicatesPaywall(bodyText)
        )
    }

    /// Truncation verdict for a capture that is about to be saved.
    ///
    /// - A DOM gate marker flags the capture unconditionally — the CTA renders
    ///   only on gated views, so even a long capture with one present is
    ///   suspect (e.g. a harvester that banked pre-gate content).
    /// - schema.org alone flags only when `extractedWordCount` is under
    ///   `PaywallRules.substantialWordFloor`: substantial content with no gate
    ///   CTA on the page is the signature of an authenticated full fetch, and
    ///   the schema value would say "false" forever regardless.
    static func verdict(_ signals: Signals, extractedWordCount: Int) -> Result {
        if signals.domGateMarker {
            return Result(isPaywalled: true, reason: .domMarker)
        }
        if signals.schemaSaysNotFree, extractedWordCount < PaywallRules.substantialWordFloor {
            return Result(isPaywalled: true, reason: .schemaOrg)
        }
        return .free
    }

    /// Convenience: signals + verdict in one call, for callers that already
    /// know the extracted word count.
    static func detect(jsonLDBlobs: [String], bodyText: String, extractedWordCount: Int) -> Result {
        verdict(signals(jsonLDBlobs: jsonLDBlobs, bodyText: bodyText),
                extractedWordCount: extractedWordCount)
    }

    // MARK: - schema.org

    /// True when any JSON-LD blob carries `isAccessibleForFree` = false. Blobs
    /// that fail to parse are skipped (a malformed script never fails a parse).
    static func jsonLDIndicatesPaywall(_ blobs: [String]) -> Bool {
        for blob in blobs {
            guard let data = blob.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            if containsAccessibleForFreeFalse(json) { return true }
        }
        return false
    }

    /// Recursively walks the decoded JSON-LD (publishers commonly nest the
    /// article node inside an `@graph` array) looking for the key with a
    /// false-like value.
    private static func containsAccessibleForFreeFalse(_ node: Any) -> Bool {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if key.caseInsensitiveCompare(PaywallRules.accessibleForFreeKey) == .orderedSame,
                   isFalseLike(value) {
                    return true
                }
                if containsAccessibleForFreeFalse(value) { return true }
            }
        } else if let array = node as? [Any] {
            for element in array where containsAccessibleForFreeFalse(element) {
                return true
            }
        }
        return false
    }

    /// Accepts the two real-world encodings of a false schema.org boolean: the
    /// JSON boolean `false`, and the strings `"false"` / `"http://schema.org/False"`.
    private static func isFalseLike(_ value: Any) -> Bool {
        if let bool = value as? Bool { return bool == false }
        if let string = value as? String {
            let lower = string.lowercased()
            return lower == "false" || lower.hasSuffix("/false")
        }
        return false
    }

    // MARK: - In-DOM markers

    /// True when the rendered page's visible text contains a known gate CTA.
    /// Case-insensitive substring match; the phrase list is kept gate-specific
    /// so this doesn't fire on prose that merely discusses subscriptions.
    static func bodyIndicatesPaywall(_ bodyText: String) -> Bool {
        guard !bodyText.isEmpty else { return false }
        let normalized = bodyText.lowercased()
        return PaywallRules.gatePhrases.contains { normalized.contains($0) }
    }
}
