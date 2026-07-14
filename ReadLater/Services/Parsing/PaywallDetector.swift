import Foundation

/// Pure, honest paywall detection for the article pipeline.
///
/// Medium and other metered publishers serve anonymous clients only a preview:
/// the full text never reaches our off-screen WKWebView, so the parser's
/// scroll-pump faithfully captures — and would otherwise save as if complete —
/// a truncated preview. This detector reads two signals off the *rendered* page
/// and reports whether the content we got is a member-only preview:
///
/// 1. **schema.org** — a `<script type="application/ld+json">` blob whose
///    `isAccessibleForFree` is false (the confirmed ground truth for the
///    reported test article).
/// 2. **In-DOM gate markers** — the registration/subscribe calls-to-action a
///    wall shows in place of the body (`PaywallRules.gatePhrases`).
///
/// Detection is *additive*, never a quality-gate rejection: a member-only
/// preview is real prose and may legitimately pass the gate. We still save what
/// we captured (partial beats nothing) and flag it so the reader can be honest.
///
/// Pure — no WKWebView or main-actor state — so it is unit-testable directly
/// with fixtures. The JS wrapper in `ArticleParser` gathers the raw signals
/// (JSON-LD blobs + visible body text) and feeds them here.
enum PaywallDetector {

    /// Why a page was flagged. Nil `reason` means not paywalled.
    enum Reason: String, Equatable {
        /// schema.org `isAccessibleForFree:false`.
        case schemaOrg
        /// An in-DOM registration/subscribe gate marker.
        case domMarker
    }

    struct Result: Equatable {
        var isPaywalled: Bool
        var reason: Reason?

        static let free = Result(isPaywalled: false, reason: nil)
    }

    /// Runs both signals; schema.org wins first because it is unambiguous
    /// publisher metadata rather than a phrase heuristic.
    static func detect(jsonLDBlobs: [String], bodyText: String) -> Result {
        if jsonLDIndicatesPaywall(jsonLDBlobs) {
            return Result(isPaywalled: true, reason: .schemaOrg)
        }
        if bodyIndicatesPaywall(bodyText) {
            return Result(isPaywalled: true, reason: .domMarker)
        }
        return .free
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
