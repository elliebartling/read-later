import SwiftUI
import UIKit
import QuartzCore

/// SwiftUI wrapper around UITextView that:
/// 1. Renders `plainText` with existing highlights painted in place.
/// 2. Creates a highlight *immediately* when the user finishes a selection.
///    The trigger is the supported UITextViewDelegate hook
///    `textView(_:editMenuForTextIn:suggestedActions:)`, which the system
///    calls exactly when a non-empty selection is made and the edit menu is
///    about to appear. (Do NOT attach a separate UIEditMenuInteraction —
///    UITextView owns its edit menu and never consults an extra interaction,
///    so custom items would simply never show.)
/// 3. Presents a post-highlight edit menu over the selection: Color (which
///    opens the edit sheet's swatch row — H1 deleted the text-only colour
///    list), Add Note, Remove Highlight, plus the system actions.
///    Dragging the selection handles updates the same highlight instead of
///    creating duplicates — the coordinator tracks the "session" highlight ID
///    until the selection collapses.
/// 4. Detects single taps on existing highlights (reported via
///    `onTapHighlight`) so the reader can present an edit sheet. While a
///    highlight is being edited (`editingHighlightID`), its range is selected
///    so the system drag handles stay visible for in-place range adjustment.
/// 5. Reports scroll progress (0...1) so the reader can mark articles read
///    when the user actually reaches the end.
///
/// The current paragraph (spoken by TTS) can also be marked by supplying
/// `currentSpokenRange` — offsets are UTF-16, same as highlight offsets. It
/// renders as the hueless `SystemState` wash plus an `Accent.primary` leading
/// rail (H5), never as a tint that could be mistaken for a user's highlight.
struct HighlightableTextView: UIViewRepresentable {

    struct HighlightIntent: Equatable {
        /// UTF-16 offsets into `text` (from UITextView.selectedRange).
        let startOffset: Int
        let endOffset: Int
        let quotedText: String
        let color: HighlightColor
    }

    let text: String
    let highlights: [Highlight]
    let currentSpokenRange: NSRange?
    let theme: ReaderTheme
    let fontSize: CGFloat
    let fontRaw: String
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let width: ReaderWidth
    /// Color applied to instantly-created highlights (the last-used color).
    let defaultColor: HighlightColor
    /// GLOBAL UTF-16 ranges of `text` that came from inside a `<blockquote>`
    /// (`ArticleBlocks.quoteRanges`). This reader shows `plainText` as one text
    /// view, so quotes get their distinction from paragraph-style ATTRIBUTES
    /// over these ranges — never from injected marker characters, which would
    /// shift every highlight offset after the quote. Empty for articles with no
    /// blocks (legacy parses), which then render exactly as before.
    var quoteRanges: [NSRange] = []
    /// GLOBAL list-item ranges with their baked markers
    /// (`ArticleBlocks.listItemRanges`). Drives the hanging indent and the
    /// tighter intra-list spacing, both of which are paragraph-style
    /// attributes here for the same reason quotes are: the text — and every
    /// highlight offset over it — must not move.
    var listItemRanges: [ArticleBlocks.LocatedListItem] = []
    /// GLOBAL ranges of inline `<code>` spans
    /// (`ArticleBlocks.inlineCodeRanges`). Empty for articles parsed before
    /// the walker collected them, which then render exactly as before.
    var inlineCodeRanges: [NSRange] = []
    /// When non-nil, the matching highlight's range is kept selected so the
    /// user can drag the system handles to resize it (e.g. while the edit
    /// sheet is open). Cleared when editing ends.
    var editingHighlightID: UUID? = nil
    /// Persist a new highlight; returns its ID so the selection session can
    /// keep updating it. SwiftData inserts are synchronous, so this is safe.
    let onCreateHighlight: (HighlightIntent) -> UUID?
    /// The selection handles were dragged: update the session highlight's range.
    let onUpdateHighlight: (UUID, NSRange, String) -> Void
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    /// A single tap landed on an existing highlight.
    let onTapHighlight: (UUID) -> Void
    var onScrollProgress: ((Double) -> Void)? = nil
    /// Reports the UTF-16 index of the first character at the top of the
    /// viewport as the user scrolls, so the reader can persist the spot.
    var onTopCharacterOffset: ((Int) -> Void)? = nil
    /// Saved reading position as a UTF-16 character offset, restored on first
    /// layout. Zero means start at the top. Applied exactly once per view.
    var initialCharacterOffset: Int = 0
    /// Fired on a plain single tap in the body (not a selection, link, or
    /// highlight tap), so the reader can toggle its chrome the way Books/Reader do.
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = ReaderTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.dataDetectorTypes = [.link]
        tv.backgroundColor = .clear
        // Pin the text with our own insets and never let UIKit's automatic
        // safe-area adjustment move it. Revealing the chrome grows the safe
        // area, but the text position is frozen — the (translucent) nav bar
        // overlays the top instead of pushing the article down.
        tv.contentInsetAdjustmentBehavior = .never
        tv.baseTextInsets = Self.inset(for: width)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        context.coordinator.parent = self
        // Restore the saved reading position once the text has laid out and a
        // real content height exists. layoutSubviews fires repeatedly; the
        // coordinator applies the restore exactly once, then reports progress.
        tv.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.restoreScrollIfNeeded()
        }

        // Single-tap toggles the reader chrome. cancelsTouchesInView = false and
        // simultaneous recognition keep the text view's own gestures (link taps,
        // selection handles, the long-press that starts a selection) intact.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        // ReaderTextView adds the frozen safe-area padding on top of these
        // reading insets; setting the base is enough (see applyReaderInsets).
        if let reader = tv as? ReaderTextView {
            reader.baseTextInsets = Self.inset(for: width)
            // Defensive: keep UIKit from ever re-insetting the text for the bars.
            if reader.contentInsetAdjustmentBehavior != .never {
                reader.contentInsetAdjustmentBehavior = .never
            }
        }
        let signature = renderSignature()
        if signature != context.coordinator.lastRenderSignature {
            let preservedSelection = tv.selectedRange
            // Re-rendering resets the selection to zero before we restore it.
            // Suppress the selection-change callback so that transient reset
            // doesn't end the highlight session mid-selection.
            context.coordinator.suppressSelectionChange = true
            tv.attributedText = render()
            // Restore selection if it still fits — protects an in-progress highlight
            // from being wiped by unrelated SwiftUI updates (e.g. TTS paragraph advance).
            if preservedSelection.location + preservedSelection.length <= (tv.text as NSString).length {
                tv.selectedRange = preservedSelection
            }
            context.coordinator.suppressSelectionChange = false
            context.coordinator.lastRenderSignature = signature
        }

        // Enter / leave sheet-edit mode: select the highlight so drag handles
        // appear, or collapse the selection when editing ends.
        context.coordinator.applyEditingSelectionIfNeeded()

        // H5 — the wash is a text attribute (see `render()`); its rail is
        // geometry, so it lives on the text view.
        if let reader = tv as? ReaderTextView {
            reader.spokenRailColor = SystemState.railUI(darkBackground: theme.isDark)
            reader.spokenRailRange = currentSpokenRange
        }

        // Keep the spoken paragraph on screen as TTS advances.
        if currentSpokenRange?.location != context.coordinator.lastSpokenLocation {
            context.coordinator.lastSpokenLocation = currentSpokenRange?.location
            if let range = currentSpokenRange {
                context.coordinator.scrollToKeepVisible(range: range, in: tv)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Horizontal inset applied to both edges of a quoted paragraph. Roughly
    /// matches the block reader's bar + gap so the two readers set quotes in by
    /// a similar amount.
    static let quoteIndent: CGFloat = 20

    /// Reading padding. The bottom is `ReaderChrome.bottomReserve` — the
    /// floating action bar's height plus its offset plus 12pt of clearance
    /// (S5) — reserved unconditionally so the capsule never bisects a line and
    /// so text doesn't move when the bar comes and goes (S6). The same
    /// constant feeds the block reader.
    private static func inset(for width: ReaderWidth) -> UIEdgeInsets {
        UIEdgeInsets(
            top: ReaderChrome.topReading,
            left: width.horizontalInset,
            bottom: ReaderChrome.bottomReserve,
            right: width.horizontalInset
        )
    }

    private func renderSignature() -> String {
        let highlightSig = highlights
            .map { "\($0.id.uuidString):\($0.startOffset):\($0.endOffset):\($0.colorRaw)" }
            .joined(separator: "|")
        let spoken = currentSpokenRange.map { "\($0.location)-\($0.length)" } ?? ""
        let quoteSig = quoteRanges.map { "\($0.location)-\($0.length)" }.joined(separator: ",")
        let listSig = listItemRanges
            .map { "\($0.range.location)-\($0.range.length)-\($0.continuesList)" }
            .joined(separator: ",")
        let codeSig = inlineCodeRanges.map { "\($0.location)-\($0.length)" }.joined(separator: ",")
        return "\(text.utf16.count)|\(theme.rawValue)|\(fontSize)|\(fontRaw)|\(lineSpacing)|\(paragraphSpacing)|\(width.rawValue)|\(highlightSig)|\(spoken)|\(quoteSig)|\(listSig)|\(codeSig)"
    }

    // MARK: - Rendering

    /// UTF-16 ranges of the newline characters that terminate *empty*
    /// paragraphs — the 2nd..nth newline in every run of consecutive
    /// newlines. `plainText` separates paragraphs with "\n\n", so each break
    /// contains exactly one such blank paragraph.
    static func blankLineRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        var i = 0
        while i < ns.length {
            if ns.character(at: i) == 0x0A { // "\n"
                var j = i + 1
                while j < ns.length, ns.character(at: j) == 0x0A {
                    ranges.append(NSRange(location: j, length: 1))
                    j += 1
                }
                i = j
            } else {
                i += 1
            }
        }
        return ranges
    }

    private func render() -> NSAttributedString {
        let darkBackground = theme.isDark
        let font = (ReaderFont(rawValue: fontRaw) ?? .serif).uiFont(size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.foreground,
            .paragraphStyle: paragraphStyle,
        ]
        let str = NSMutableAttributedString(string: text, attributes: attrs)

        // Quote distinction in the flowed reader. This view renders `plainText`
        // as ONE text view, so there is no per-block chrome to hang a bar off
        // — and the text itself is the UTF-16 highlight offset space, so
        // injecting "> " markers here would silently move every highlight after
        // a quote. (List markers could be baked in only because that happened
        // at PARSE time, before any offset existed.) The distinction is
        // therefore attribute-only: indent both edges of the quote's paragraphs
        // and drop the text to the same secondary tone the block reader uses,
        // which reads as a set-in quote without touching a single character.
        if !quoteRanges.isEmpty {
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.lineSpacing = lineSpacing
            quoteStyle.paragraphSpacing = paragraphSpacing
            quoteStyle.firstLineHeadIndent = Self.quoteIndent
            quoteStyle.headIndent = Self.quoteIndent
            // Negative tailIndent measures in from the trailing margin, so the
            // quote is inset symmetrically.
            quoteStyle.tailIndent = -Self.quoteIndent
            let quoteAttrs: [NSAttributedString.Key: Any] = [
                .paragraphStyle: quoteStyle,
                .foregroundColor: theme.foreground.withAlphaComponent(0.7),
            ]
            let length = (text as NSString).length
            for range in quoteRanges {
                guard range.location >= 0, range.length > 0,
                      range.location + range.length <= length else { continue }
                str.addAttributes(quoteAttrs, range: range)
            }
        }

        // **Hanging indents and list grouping** (fix #4). A marker-baked list
        // item carries "• " / "3. " at the head of its own text, so with a
        // plain paragraph style its wrapped lines align under the BULLET.
        // Indenting continuation lines by the marker's measured width — and
        // only continuation lines — restores the shape, and closing the gap
        // between consecutive items makes the list read as one group instead
        // of N paragraphs. Both are attributes over verified ranges; not one
        // character of `text` changes.
        if !listItemRanges.isEmpty {
            let listSpacing = ReaderTypography.listItemSpacing(paragraphSpacing: paragraphSpacing)
            let length = (text as NSString).length
            for item in listItemRanges {
                let range = item.range
                guard range.location >= 0, range.length > 0,
                      range.location + range.length <= length else { continue }
                // Start from whatever style already applies (a quoted list item
                // keeps its quote inset) rather than replacing it.
                let base = str.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                    as? NSParagraphStyle
                let style = (base?.mutableCopy() as? NSMutableParagraphStyle)
                    ?? NSMutableParagraphStyle()
                if base == nil {
                    style.lineSpacing = lineSpacing
                    style.paragraphSpacing = paragraphSpacing
                }
                let markerWidth = ReaderTypography.markerWidth(item.markerPrefix, font: font)
                style.headIndent = style.firstLineHeadIndent + markerWidth
                if item.continuesList { style.paragraphSpacing = listSpacing }
                str.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }

        // **Inline code** (fix #4). Monospaced on the code panel's own wash, so
        // a `snippet` inside a sentence reads as the same material as a fenced
        // block instead of as undifferentiated body text.
        if !inlineCodeRanges.isEmpty {
            let codeFont = ReaderTypography.inlineCodeFont(bodySize: fontSize)
            let wash = ReaderTypography.inlineCodeBackground(foreground: theme.foreground)
            let length = (text as NSString).length
            for range in inlineCodeRanges {
                guard range.location >= 0, range.length > 0,
                      range.location + range.length <= length else { continue }
                str.addAttributes([.font: codeFont, .backgroundColor: wash], range: range)
            }
        }

        // The parser separates paragraphs with a blank line ("\n\n"). Rendered
        // literally, that empty paragraph adds a full line box plus a second
        // round of paragraphSpacing — dwarfing the user's spacing setting. The
        // text (and therefore highlight offsets) must stay untouched, so
        // instead collapse each blank line to near-zero height, making
        // `paragraphSpacing` the single source of inter-paragraph space.
        let collapsedStyle = NSMutableParagraphStyle()
        collapsedStyle.maximumLineHeight = 1
        collapsedStyle.lineSpacing = 0
        collapsedStyle.paragraphSpacing = 0
        let collapsedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 1),
            .paragraphStyle: collapsedStyle,
        ]
        for range in Self.blankLineRanges(in: text) {
            str.addAttributes(collapsedAttrs, range: range)
        }

        for h in highlights {
            if let located = HighlightAnchor.locate(
                in: text,
                startOffset: h.startOffset,
                endOffset: h.endOffset,
                quotedText: h.quotedText,
                prefixContext: h.prefixContext,
                suffixContext: h.suffixContext
            ) {
                let nsRange = NSRange(located.range, in: text)
                str.addAttribute(.backgroundColor, value: h.color.uiColor(darkBackground: darkBackground), range: nsRange)
            }
        }

        // **H5.** Reading position is machine state, not annotation. It used to
        // paint a pale yellow band — visually identical to a yellow highlight,
        // so while listening you couldn't tell your own marks from the cursor
        // (audit theme 7). It is now the hueless `SystemState` wash, derived
        // from this page's own paper, plus the leading rail drawn by
        // `ReaderTextView`.
        if let range = currentSpokenRange, range.location + range.length <= (text as NSString).length {
            let wash = SystemState.washUI(
                overPaper: theme.background,
                darkBackground: darkBackground
            )
            str.addAttribute(.backgroundColor, value: wash, range: range)
        }
        return str
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var textView: UITextView?
        var parent: HighlightableTextView?
        var lastRenderSignature: String = ""
        var lastSpokenLocation: Int?
        /// Set while updateUIView programmatically resets/restores the selection.
        var suppressSelectionChange = false

        /// The highlight created by the current selection "session". Handle
        /// drags update this highlight instead of creating duplicates; the
        /// session ends when the selection collapses to zero length (unless
        /// sheet-edit mode is holding it open via `editingHighlightID`).
        private var activeHighlightID: UUID?
        /// Last `editingHighlightID` we applied a selection for — avoids
        /// re-selecting on every SwiftUI tick while the sheet is open.
        private var appliedEditingHighlightID: UUID?

        /// Whether the saved reading position has been applied yet. Progress is
        /// not reported until this is true, so the initial top-of-document
        /// scroll can't overwrite the saved spot before we restore it.
        private var didRestoreScroll = false

        /// True while the user's finger is driving the scroll view (drag or the
        /// momentum that follows). Used to reject taps that are really the tail
        /// end of a scroll so the chrome doesn't toggle while reading.
        private var isUserScrolling = false
        /// Timestamp of the last user-driven scroll. A tap within a short window
        /// after scrolling is treated as part of that gesture, not a chrome tap.
        private var lastScrollTime: CFTimeInterval = 0
        /// How long after a scroll a tap is still considered "part of scrolling".
        private let scrollTapCooldown: CFTimeInterval = 0.25

        /// Restores the saved reading position on first layout, then unblocks
        /// progress reporting. Runs once: either it scrolls the saved character
        /// to the top of the viewport (once the text has laid out) or, when
        /// there's nothing to restore, marks restoration done so live progress
        /// can flow.
        func restoreScrollIfNeeded() {
            guard !didRestoreScroll, let tv = textView, let parent = parent else { return }

            // Shared with the block reader (ReadingPosition) so both readers
            // treat "nothing saved" and "the text shrank past the saved spot"
            // identically — start at the top and report immediately.
            guard let offset = ReadingPosition.resolvedOffset(
                saved: parent.initialCharacterOffset,
                textLength: (tv.text as NSString).length
            ) else {
                didRestoreScroll = true
                return
            }

            // Wait for a real layout before trusting caret geometry.
            guard tv.bounds.height > 0, tv.contentSize.height > 0 else { return }

            // Caret geometry (UITextInput) rather than layoutManager so we stay
            // on TextKit 2 — see characterIndex(at:in:) for why that matters.
            guard let position = tv.position(from: tv.beginningOfDocument, offset: offset) else {
                didRestoreScroll = true
                return
            }
            let caret = tv.caretRect(for: position)
            guard caret.minY.isFinite else {
                didRestoreScroll = true
                return
            }

            let targetY = Self.restoreOffsetY(
                caretMinY: caret.minY,
                contentHeight: tv.contentSize.height,
                viewportHeight: tv.bounds.height,
                topInset: tv.adjustedContentInset.top,
                bottomInset: tv.adjustedContentInset.bottom
            )
            didRestoreScroll = true
            tv.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
        }

        /// UTF-16 index of the first character at the top of the viewport, used
        /// to persist the reading spot. Nil until the text has laid out.
        func topCharacterOffset(in tv: UITextView) -> Int? {
            let length = (tv.text as NSString).length
            guard length > 0 else { return nil }
            // Just below the top of the visible text area (past the safe-area /
            // nav-bar inset), a hair inside the left margin.
            let topY = tv.contentOffset.y + tv.adjustedContentInset.top + 1
            let point = CGPoint(x: tv.textContainerInset.left + 1, y: topY)
            guard let position = tv.closestPosition(to: point) else { return nil }
            let index = tv.offset(from: tv.beginningOfDocument, to: position)
            guard index >= 0, index <= length else { return nil }
            return index
        }

        /// Content offset that scrolls the saved character's caret to the top of
        /// the viewport, clamped to the scroll view's valid range. Pure so it
        /// can be unit-tested without UIKit.
        static func restoreOffsetY(
            caretMinY: CGFloat,
            contentHeight: CGFloat,
            viewportHeight: CGFloat,
            topInset: CGFloat,
            bottomInset: CGFloat
        ) -> CGFloat {
            let target = caretMinY - topInset
            let minY = -topInset
            let maxY = max(minY, contentHeight - viewportHeight + bottomInset)
            // A caret within the first `topInset` of content means the reader
            // was at the very start — snap to the true top rather than hiding
            // a sliver of the article above the caret.
            guard target >= 0 else { return minY }
            return min(max(target, minY), maxY)
        }

        /// Scrolls so the spoken paragraph stays visible while TTS advances,
        /// without hijacking the view when the user is reading elsewhere.
        func scrollToKeepVisible(range: NSRange, in tv: UITextView) {
            // Never fight the user's finger.
            guard !tv.isTracking, !tv.isDragging, !tv.isDecelerating else { return }
            guard range.location + range.length <= (tv.text as NSString).length else { return }

            // UITextInput geometry (not layoutManager) so we don't downgrade the
            // text view off TextKit 2 — see characterIndex(at:in:) for why.
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let textRange = tv.textRange(from: start, to: end) else { return }
            let rect = tv.firstRect(for: textRange)
            guard !rect.isNull, rect.minY.isFinite else { return }

            let visibleTop = tv.contentOffset.y + tv.adjustedContentInset.top
            let visibleHeight = tv.bounds.height - tv.adjustedContentInset.top - tv.adjustedContentInset.bottom
            let visibleBottom = visibleTop + visibleHeight

            // Only move when the paragraph's start drifts out of the
            // comfortable band (with some margin for the player capsule).
            let margin: CGFloat = 90
            guard rect.minY < visibleTop + 8 || rect.minY > visibleBottom - margin else { return }

            // Place the paragraph in the upper third, clamped to content.
            let targetY = rect.minY - visibleHeight / 3
            let maxOffset = max(-tv.adjustedContentInset.top,
                                tv.contentSize.height - tv.bounds.height + tv.adjustedContentInset.bottom)
            let clamped = min(max(-tv.adjustedContentInset.top, targetY - tv.adjustedContentInset.top), maxOffset)
            tv.setContentOffset(CGPoint(x: 0, y: clamped), animated: true)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let tv = textView else { return }
            // A tap that lands on an active selection or a link is meant for
            // the text view (dismiss selection / open link), not chrome toggling.
            if tv.selectedRange.length > 0 { return }
            // Reject taps that are really part of scrolling: a finger lifting
            // after a flick, a tap that stops momentum, or one that lands just
            // after the page settles. This keeps chrome from toggling while the
            // user is only scrolling.
            if isUserScrolling || tv.isDragging || tv.isDecelerating { return }
            if CACurrentMediaTime() - lastScrollTime < scrollTapCooldown { return }
            let point = gesture.location(in: tv)
            if isLink(at: point, in: tv) { return }
            if let highlightID = highlightID(at: point, in: tv) {
                parent?.onTapHighlight(highlightID)
                return
            }
            parent?.onTap?()
        }

        /// True if `point` falls on a `.link`-attributed glyph.
        private func isLink(at point: CGPoint, in tv: UITextView) -> Bool {
            guard let index = characterIndex(at: point, in: tv) else { return false }
            guard let attributed = tv.attributedText, index < attributed.length else { return false }
            return attributed.attribute(.link, at: index, effectiveRange: nil) != nil
        }

        /// ID of the highlight whose range contains `point`, if any.
        private func highlightID(at point: CGPoint, in tv: UITextView) -> UUID? {
            guard let parent = parent, !parent.highlights.isEmpty,
                  let index = characterIndex(at: point, in: tv) else { return nil }
            for h in parent.highlights {
                if let located = HighlightAnchor.locate(
                    in: parent.text,
                    startOffset: h.startOffset,
                    endOffset: h.endOffset,
                    quotedText: h.quotedText,
                    prefixContext: h.prefixContext,
                    suffixContext: h.suffixContext
                ), index >= located.startOffset, index < located.endOffset {
                    return h.id
                }
            }
            return nil
        }

        /// Character index at `point`, computed via UITextInput geometry.
        ///
        /// Deliberately avoids `layoutManager`/`textStorage`: touching either
        /// permanently downgrades the text view from TextKit 2 to TextKit 1,
        /// which re-renders highlights as solid blocks and makes UIKit re-apply
        /// the safe-area inset (shifting the whole article down). Everything here
        /// stays on TextKit 2.
        private func characterIndex(at point: CGPoint, in tv: UITextView) -> Int? {
            let length = (tv.text as NSString).length
            guard length > 0, let position = tv.closestPosition(to: point) else { return nil }
            let index = tv.offset(from: tv.beginningOfDocument, to: position)
            guard index >= 0, index < length else { return nil }
            // `closestPosition` snaps to the nearest glyph even when the tap is in
            // the margins, so confirm the point is actually on that line — blank
            // taps should toggle the chrome, not land on a nearby highlight.
            let caret = tv.caretRect(for: position)
            guard caret.minY.isFinite, caret.height > 0,
                  point.y >= caret.minY - 4, point.y <= caret.maxY + 4 else { return nil }
            return index
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Selects the highlight being edited so the system drag handles appear,
        /// or clears the selection when sheet-edit mode ends.
        func applyEditingSelectionIfNeeded() {
            guard let parent = parent, let tv = textView else { return }
            let editingID = parent.editingHighlightID
            guard editingID != appliedEditingHighlightID else { return }
            appliedEditingHighlightID = editingID

            guard let id = editingID,
                  let h = parent.highlights.first(where: { $0.id == id }),
                  let located = HighlightAnchor.locate(
                    in: parent.text,
                    startOffset: h.startOffset,
                    endOffset: h.endOffset,
                    quotedText: h.quotedText,
                    prefixContext: h.prefixContext,
                    suffixContext: h.suffixContext
                  ) else {
                // Editing ended — collapse selection and clear the session
                // unless a fresh selection is already in progress.
                if editingID == nil, activeHighlightID != nil || tv.selectedRange.length > 0 {
                    endSession(collapseSelection: true)
                }
                return
            }

            let range = NSRange(located.range, in: parent.text)
            activeHighlightID = id
            suppressSelectionChange = true
            tv.selectedRange = range
            suppressSelectionChange = false
            // Bring the selection into view so handles aren't hidden under the sheet.
            tv.scrollRangeToVisible(range)
        }

        // The system calls this the moment a non-empty selection settles and
        // the edit menu is about to appear — our trigger for instant highlighting.
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let parent = parent,
                  let swiftRange = Range(range, in: parent.text) else {
                return UIMenu(children: suggestedActions)
            }
            let quoted = String(parent.text[swiftRange])

            // Sheet-edit mode: resize the highlight under edit, skip creating
            // a duplicate, and keep the menu light (the sheet owns color/note/delete).
            if let editingID = parent.editingHighlightID {
                activeHighlightID = editingID
                parent.onUpdateHighlight(editingID, range, quoted)
                return UIMenu(children: suggestedActions)
            }

            let highlightID: UUID
            if let active = activeHighlightID {
                // Handle drag re-invoked the menu: move the session highlight.
                parent.onUpdateHighlight(active, range, quoted)
                highlightID = active
            } else {
                let intent = HighlightIntent(
                    startOffset: range.location,
                    endOffset: range.location + range.length,
                    quotedText: quoted,
                    color: parent.defaultColor
                )
                guard let id = parent.onCreateHighlight(intent) else {
                    return UIMenu(children: suggestedActions)
                }
                activeHighlightID = id
                highlightID = id
            }

            // H1 — the text-only colour list ("Yellow / Green / Blue / Pink",
            // showing no colour at all) is deleted. `Color` opens the edit
            // sheet, whose swatch row is the app's only picker. Both readers
            // make the same move; a change here must land in the block
            // reader's menu too (AGENTS.md, "There are two readers").
            let color = UIAction(
                title: "Color"
            ) { [weak self] _ in
                self?.parent?.onTapHighlight(highlightID)
            }
            let addNote = UIAction(
                title: "Add note"
            ) { [weak self] _ in
                // Keep the selection + session so drag handles stay visible
                // behind the edit sheet for in-place range adjustment.
                self?.parent?.onRequestNote(highlightID)
            }
            let remove = UIAction(
                title: "Remove highlight",
                attributes: .destructive
            ) { [weak self] _ in
                self?.endSession(collapseSelection: true)
                self?.parent?.onDeleteHighlight(highlightID)
            }
            return UIMenu(children: [color, addNote, remove] + suggestedActions)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // The instantly-created highlight already shows the selected range;
            // keep the system's blue selection wash from painting over it.
            // (Re-applied on every change because UIKit re-shows the view when
            // the selection re-activates.)
            (textView as? ReaderTextView)?.hideSelectionHighlight()
            guard !suppressSelectionChange else { return }
            // Selection collapsed: end the session unless sheet-edit mode is
            // holding the highlight open (we'll re-select on the next update).
            // Range updates themselves happen in editMenuForTextIn when the
            // selection settles after a handle drag — avoids thrashing SwiftData
            // on every pixel of movement.
            if textView.selectedRange.length == 0, parent?.editingHighlightID == nil {
                activeHighlightID = nil
            }
        }

        /// Forgets the session highlight, optionally collapsing the selection.
        private func endSession(collapseSelection: Bool) {
            activeHighlightID = nil
            guard collapseSelection, let tv = textView, tv.selectedRange.length > 0 else { return }
            suppressSelectionChange = true
            tv.selectedRange = NSRange(location: tv.selectedRange.location, length: 0)
            suppressSelectionChange = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Only user-driven movement should arm the tap cooldown; programmatic
            // scrolls (TTS follow, bring-selection-into-view) must not.
            if scrollView.isDragging || scrollView.isDecelerating {
                lastScrollTime = CACurrentMediaTime()
            }
            // Hold off until the saved position is restored so the initial
            // top-of-document offset can't be reported (and saved) as progress.
            guard didRestoreScroll else { return }
            let total = scrollView.contentSize.height
            guard total > 0 else { return }

            // Fraction drives the "X min left" subtitle and read-tracking.
            if let onProgress = parent?.onScrollProgress {
                let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
                onProgress(min(1.0, max(0.0, Double(visibleBottom / total))))
            }
            // Character offset is the persisted anchor for resuming the spot.
            if let onOffset = parent?.onTopCharacterOffset, let tv = textView,
               let index = topCharacterOffset(in: tv) {
                onOffset(index)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            lastScrollTime = CACurrentMediaTime()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            lastScrollTime = CACurrentMediaTime()
            if !decelerate { isUserScrolling = false }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserScrolling = false
            lastScrollTime = CACurrentMediaTime()
        }
    }
}

/// A UITextView that keeps the article text in a fixed position regardless of
/// the reader chrome.
///
/// The text's top padding is frozen at the *immersive* safe-area inset (notch /
/// status bar, chrome hidden). When the nav bar is later revealed the safe area
/// grows, but we keep using the frozen value, so the text never shifts — the
/// translucent bar simply overlays it. `contentInsetAdjustmentBehavior` is
/// `.never` (set by the representable) so UIKit doesn't re-inset either.
final class ReaderTextView: SelectionWashHidingTextView {
    /// Reading padding (top/bottom breathing room + width-based side margins)
    /// supplied by the representable. Safe-area accommodation is layered on top.
    var baseTextInsets: UIEdgeInsets = .zero {
        didSet { if baseTextInsets != oldValue { applyReaderInsets() } }
    }

    /// The top safe-area inset while the chrome is hidden. Frozen at its minimum
    /// so revealing the nav bar (which enlarges the safe area) can't move the text.
    private var immersiveTopInset: CGFloat?

    /// Called after every layout pass, once the content size is up to date. The
    /// coordinator uses it to restore the saved reading position on first paint.
    var onLayout: (() -> Void)?

    /// **H5.** The spoken paragraph's leading rail — the companion to the
    /// hueless `SystemState` wash painted as a background attribute. UTF-16
    /// range, nil when TTS is idle. The block reader draws the same rail in
    /// SwiftUI; the two must stay in step (AGENTS.md, "There are two readers").
    var spokenRailRange: NSRange? {
        didSet { if spokenRailRange != oldValue { setNeedsLayout() } }
    }

    /// Rail colour, resolved for the reader *page's* darkness rather than the
    /// UI scheme (a light-mode app can be showing a dark paper).
    var spokenRailColor: UIColor = SystemState.railUI(darkBackground: false) {
        didSet { railLayer.backgroundColor = spokenRailColor.cgColor }
    }

    /// Gap between the rail and the text column's leading edge.
    private static let railGap: CGFloat = 8

    private lazy var railLayer: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = SystemState.railWidth / 2
        layer.cornerCurve = .continuous
        layer.isHidden = true
        // Not `.zero` — the layer lives in the scroll view's content space, so
        // it must not animate as the content scrolls under it.
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        self.layer.addSublayer(layer)
        return layer
    }()

    /// Places (or hides) the rail beside the spoken range. Uses UITextInput
    /// geometry rather than the layout manager so it works identically under
    /// TextKit 2 and the TextKit 1 compatibility fallback.
    private func layoutSpokenRail() {
        guard let range = spokenRailRange,
              range.length > 0,
              range.location + range.length <= (text as NSString).length,
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = self.textRange(from: start, to: end)
        else {
            railLayer.isHidden = true
            return
        }
        let rects = selectionRects(for: textRange)
            .map(\.rect)
            .filter { $0.height > 0 && $0.width.isFinite && $0.origin.y.isFinite }
        guard let first = rects.first else {
            railLayer.isHidden = true
            return
        }
        let minY = rects.reduce(first.minY) { min($0, $1.minY) }
        let maxY = rects.reduce(first.maxY) { max($0, $1.maxY) }
        let x = max(2, textContainerInset.left - SystemState.railWidth - Self.railGap)
        railLayer.backgroundColor = spokenRailColor.cgColor
        railLayer.frame = CGRect(
            x: x,
            y: minY,
            width: SystemState.railWidth,
            height: max(SystemState.railWidth, maxY - minY)
        )
        railLayer.isHidden = false
    }

    override func layoutSubviews() {
        // Re-assert the reader insets on EVERY layout pass, not only when the
        // safe area changes. UIKit can reset `textContainerInset` and
        // `lineFragmentPadding` behind our back (most notably when a text view
        // falls back from TextKit 2 to TextKit 1 and swaps its text container;
        // also seen around bar/chrome transitions). Before this ran per-pass,
        // such a reset was STICKY: nothing re-applied the insets until the next
        // safe-area change, so the article rendered flush against the screen
        // edge — seen on device during TTS with the audio capsule up. The
        // equality guards inside applyReaderInsets keep this a no-op on the
        // (overwhelmingly common) already-correct pass.
        applyReaderInsets()
        // `super` (SelectionWashHidingTextView) lays out the text view and then
        // re-hides the selection wash; we only need to add the layout callback.
        super.layoutSubviews()
        layoutSpokenRail()
        onLayout?()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        applyReaderInsets()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyReaderInsets()
    }

    /// Pure inset math for the frozen-top reader padding, extracted so it can
    /// be unit-tested without UIKit layout. Returns the container insets to
    /// apply plus the updated frozen-top value to store.
    ///
    /// Rules:
    /// - left/right come from `base` only — the safe area NEVER moves the text
    ///   horizontally (portrait phones have no horizontal safe area; the reader
    ///   opts out of everything else).
    /// - top freezes at the smallest positive safe-area top ever seen (the
    ///   immersive, chrome-hidden value), so revealing the nav bar can't push
    ///   the article down. A transient 0 (mid-transition, detached view) never
    ///   unfreezes or shrinks it.
    /// - bottom follows the live safe area.
    static func frozenReaderInsets(
        base: UIEdgeInsets,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        frozenTop: CGFloat?
    ) -> (insets: UIEdgeInsets, frozenTop: CGFloat?) {
        // Shared with the block reader so the two readers cannot drift.
        let frozen = ReaderChrome.frozenTop(live: safeAreaTop, frozen: frozenTop)
        let insets = UIEdgeInsets(
            top: base.top + (frozen ?? safeAreaTop),
            left: base.left,
            bottom: base.bottom + safeAreaBottom,
            right: base.right
        )
        return (insets, frozen)
    }

    private func applyReaderInsets() {
        let liveTop = safeAreaInsets.top
        let result = Self.frozenReaderInsets(
            base: baseTextInsets,
            safeAreaTop: liveTop,
            safeAreaBottom: safeAreaInsets.bottom,
            frozenTop: immersiveTopInset
        )
        immersiveTopInset = result.frozenTop
        if textContainerInset != result.insets {
            textContainerInset = result.insets
        }
        // The representable zeroes lineFragmentPadding once at creation, but a
        // container swap (TextKit 1 fallback) restores UIKit's default 5pt —
        // pin it here so the healing pass covers it too.
        if textContainer.lineFragmentPadding != 0 {
            textContainer.lineFragmentPadding = 0
        }
        // Defensive: UIKit must never re-inset the content for the bars; the
        // frozen top inset above is the single source of truth.
        if contentInsetAdjustmentBehavior != .never {
            contentInsetAdjustmentBehavior = .never
        }

        // Scroll indicators should still dodge the *live* bars, not the frozen
        // inset — the scrollbar tucking under the nav bar looks broken.
        let indicator = UIEdgeInsets(top: liveTop, left: 0, bottom: safeAreaInsets.bottom, right: 0)
        if verticalScrollIndicatorInsets != indicator {
            verticalScrollIndicatorInsets = indicator
        }
    }
}
