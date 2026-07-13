import Foundation

/// Pure planner that folds a new highlight selection together with any existing
/// highlights it overlaps — or merely touches — on the same article, so that
/// re-highlighting over an existing highlight grows one highlight instead of
/// stacking overlapping duplicates.
///
/// All offsets are **UTF-16 code units**, the same unit as
/// `UITextView.selectedRange` (NSRange), which is where highlight offsets
/// originate. Interpreting them as Swift `Character` offsets silently misplaces
/// merges in any article containing emoji or other non-BMP characters — the
/// planner therefore measures and re-derives text through `NSString`.
///
/// `plan` is intentionally free of SwiftData: it takes value-type snapshots of
/// the existing highlights and returns a value-type `Plan`, so the merge policy
/// is exhaustively unit-testable without a `ModelContext`. The caller
/// (`ReaderView`) applies the plan: it grows the surviving highlight to the
/// union range, folds in the absorbed notes, and deletes the absorbed records.
enum HighlightMerge {

    /// A SwiftData-free snapshot of an existing highlight — only the fields the
    /// planner needs.
    struct Existing {
        let id: UUID
        /// UTF-16 offset, inclusive start.
        let startOffset: Int
        /// UTF-16 offset, exclusive end.
        let endOffset: Int
        let note: String?
        let createdAt: Date

        init(id: UUID, startOffset: Int, endOffset: Int, note: String? = nil, createdAt: Date) {
            self.id = id
            self.startOffset = startOffset
            self.endOffset = endOffset
            self.note = note
            self.createdAt = createdAt
        }
    }

    struct Plan: Equatable {
        /// UTF-16 union spanning the new selection and every absorbed highlight.
        let unionStart: Int
        /// UTF-16 exclusive end of the union.
        let unionEnd: Int
        /// `quotedText` re-derived verbatim from the article plain text for the
        /// union range, so the render-time fallback search still re-anchors it.
        let quotedText: String
        /// Existing highlights fully merged into the union — the caller deletes
        /// these records. Ordered by document position.
        let absorbed: [UUID]
        /// Notes gathered from every absorbed highlight, in document order,
        /// joined with `noteSeparator` so nothing is lost. Nil when no absorbed
        /// highlight carried a (non-blank) note.
        let absorbedNote: String?
        /// Earliest `createdAt` among absorbed highlights, so the survivor can
        /// adopt the oldest timestamp. Nil when nothing was absorbed.
        let earliestCreatedAt: Date?

        /// True when the new selection touched at least one existing highlight.
        var didMerge: Bool { !absorbed.isEmpty }
    }

    /// Separator joining notes from multiple absorbed highlights.
    static let noteSeparator = "\n\n"

    /// Plans the merge of a new `[newStart, newEnd)` selection against
    /// `existing` highlights over `plainText`.
    ///
    /// Absorption is overlap-**or**-touch: a highlight is folded in when it
    /// shares any interior with the running union or sits flush against it
    /// (adjacent endpoints). Absorbing one highlight extends the union, which
    /// can then reach another — the planner iterates to a fixed point so the
    /// result is a single contiguous span with no remaining overlap or
    /// adjacency (matching "merge into one highlight spanning the union").
    static func plan(
        newStart: Int,
        newEnd: Int,
        existing: [Existing],
        plainText: String
    ) -> Plan {
        let ns = plainText as NSString

        // Normalise + clamp the incoming selection into the text's bounds.
        var lo = max(0, min(newStart, newEnd))
        var hi = min(ns.length, max(newStart, newEnd))
        if hi < lo { hi = lo }

        var absorbedSet: Set<UUID> = []
        var changed = true
        while changed {
            changed = false
            for h in existing where !absorbedSet.contains(h.id) {
                let hLo = min(h.startOffset, h.endOffset)
                let hHi = max(h.startOffset, h.endOffset)
                // Half-open [lo,hi) and [hLo,hHi) overlap OR touch iff
                // hLo <= hi && lo <= hHi. (A gap on either side fails one test.)
                guard hLo <= hi, lo <= hHi else { continue }
                absorbedSet.insert(h.id)
                lo = min(lo, hLo)
                hi = max(hi, hHi)
                changed = true
            }
        }

        // Absorbed highlights in document order (then createdAt) for a stable,
        // deterministic note join and id list.
        let absorbedHighlights = existing
            .filter { absorbedSet.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.startOffset != rhs.startOffset { return lhs.startOffset < rhs.startOffset }
                return lhs.createdAt < rhs.createdAt
            }

        let quoted: String = {
            guard lo >= 0, hi <= ns.length, lo < hi else { return "" }
            return ns.substring(with: NSRange(location: lo, length: hi - lo))
        }()

        let notes = absorbedHighlights
            .compactMap { $0.note?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let absorbedNote = notes.isEmpty ? nil : notes.joined(separator: noteSeparator)

        return Plan(
            unionStart: lo,
            unionEnd: hi,
            quotedText: quoted,
            absorbed: absorbedHighlights.map(\.id),
            absorbedNote: absorbedNote,
            earliestCreatedAt: absorbedHighlights.map(\.createdAt).min()
        )
    }

    /// Combines the survivor's existing note with the folded-in absorbed notes,
    /// dropping blanks and joining with `noteSeparator`. Returns nil when the
    /// result is empty, so a note-less merge stays note-less.
    static func combineNotes(_ survivorNote: String?, _ absorbedNote: String?) -> String? {
        let parts = [survivorNote, absorbedNote]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: noteSeparator)
    }
}
