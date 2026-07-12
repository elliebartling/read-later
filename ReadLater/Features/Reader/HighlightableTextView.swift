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
/// 3. Presents a post-highlight edit menu over the selection: Color submenu,
///    Add Note, Remove Highlight, plus the system actions (Copy, Share, …).
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
/// The current paragraph (spoken by TTS) can also be tinted by supplying
/// `currentSpokenRange` — offsets are UTF-16, same as highlight offsets.
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
    /// When non-nil, the matching highlight's range is kept selected so the
    /// user can drag the system handles to resize it (e.g. while the edit
    /// sheet is open). Cleared when editing ends.
    var editingHighlightID: UUID? = nil
    /// Persist a new highlight; returns its ID so the selection session can
    /// keep updating it. SwiftData inserts are synchronous, so this is safe.
    let onCreateHighlight: (HighlightIntent) -> UUID?
    /// The selection handles were dragged: update the session highlight's range.
    let onUpdateHighlight: (UUID, NSRange, String) -> Void
    let onRecolorHighlight: (UUID, HighlightColor) -> Void
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    /// A single tap landed on an existing highlight.
    let onTapHighlight: (UUID) -> Void
    var onScrollProgress: ((Double) -> Void)? = nil
    /// Saved reading position (0...1 scroll fraction) to restore on first
    /// layout. Zero means start at the top. Applied exactly once per view.
    var initialProgress: Double = 0
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

        // Keep the spoken paragraph on screen as TTS advances.
        if currentSpokenRange?.location != context.coordinator.lastSpokenLocation {
            context.coordinator.lastSpokenLocation = currentSpokenRange?.location
            if let range = currentSpokenRange {
                context.coordinator.scrollToKeepVisible(range: range, in: tv)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func inset(for width: ReaderWidth) -> UIEdgeInsets {
        UIEdgeInsets(top: 24, left: width.horizontalInset, bottom: 40, right: width.horizontalInset)
    }

    private func renderSignature() -> String {
        let highlightSig = highlights
            .map { "\($0.id.uuidString):\($0.startOffset):\($0.endOffset):\($0.colorRaw)" }
            .joined(separator: "|")
        let spoken = currentSpokenRange.map { "\($0.location)-\($0.length)" } ?? ""
        return "\(text.utf16.count)|\(theme.rawValue)|\(fontSize)|\(fontRaw)|\(lineSpacing)|\(paragraphSpacing)|\(width.rawValue)|\(highlightSig)|\(spoken)"
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
                quotedText: h.quotedText
            ) {
                let nsRange = NSRange(located.range, in: text)
                str.addAttribute(.backgroundColor, value: h.color.uiColor(darkBackground: darkBackground), range: nsRange)
            }
        }

        if let range = currentSpokenRange, range.location + range.length <= (text as NSString).length {
            let spokenTint: UIColor = darkBackground
                ? UIColor(white: 1, alpha: 0.14)
                : UIColor.systemYellow.withAlphaComponent(0.16)
            str.addAttribute(.backgroundColor, value: spokenTint, range: range)
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
        private var activeColor: HighlightColor?
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
        /// progress reporting. Runs once: either it applies the saved fraction
        /// (once content is tall enough to scroll) or, when there's nothing to
        /// restore, it simply marks restoration done so live progress can flow.
        func restoreScrollIfNeeded() {
            guard !didRestoreScroll, let tv = textView, let parent = parent else { return }

            let fraction = parent.initialProgress
            // Nothing meaningful saved — start at the top and report immediately.
            guard fraction > 0.0001 else {
                didRestoreScroll = true
                return
            }

            // Wait for a real layout: a valid viewport and content taller than it.
            let content = tv.contentSize.height
            let viewport = tv.bounds.height
            guard viewport > 0, content > 0 else { return }

            let offset = Self.restoreOffset(
                fraction: fraction,
                contentHeight: content,
                viewportHeight: viewport,
                topInset: tv.adjustedContentInset.top,
                bottomInset: tv.adjustedContentInset.bottom
            )
            didRestoreScroll = true
            tv.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }

        /// Content offset that puts the saved reading position back on screen.
        ///
        /// `fraction` is visibleBottom / contentHeight (matching the metric
        /// reported by `scrollViewDidScroll`), so the matching top offset is
        /// `fraction * contentHeight - viewportHeight`, clamped to the scroll
        /// view's valid range. Pure so it can be unit-tested without UIKit.
        static func restoreOffset(
            fraction: Double,
            contentHeight: CGFloat,
            viewportHeight: CGFloat,
            topInset: CGFloat,
            bottomInset: CGFloat
        ) -> CGFloat {
            let target = CGFloat(fraction) * contentHeight - viewportHeight
            let minY = -topInset
            let maxY = max(minY, contentHeight - viewportHeight + bottomInset)
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
                    quotedText: h.quotedText
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
                    quotedText: h.quotedText
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
            activeColor = h.color
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
                activeColor = parent.defaultColor
                highlightID = id
            }

            let colorActions = HighlightColor.allCases.map { color in
                UIAction(title: color.displayName,
                         state: color == activeColor ? .on : .off) { [weak self] _ in
                    self?.activeColor = color
                    self?.parent?.onRecolorHighlight(highlightID, color)
                }
            }
            let colorMenu = UIMenu(
                title: "Color",
                image: UIImage(systemName: "highlighter"),
                children: colorActions
            )
            let addNote = UIAction(
                title: "Add Note",
                image: UIImage(systemName: "note.text.badge.plus")
            ) { [weak self] _ in
                // Keep the selection + session so drag handles stay visible
                // behind the edit sheet for in-place range adjustment.
                self?.parent?.onRequestNote(highlightID)
            }
            let remove = UIAction(
                title: "Remove Highlight",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.endSession(collapseSelection: true)
                self?.parent?.onDeleteHighlight(highlightID)
            }
            return UIMenu(children: [colorMenu, addNote, remove] + suggestedActions)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !suppressSelectionChange else { return }
            // Selection collapsed: end the session unless sheet-edit mode is
            // holding the highlight open (we'll re-select on the next update).
            // Range updates themselves happen in editMenuForTextIn when the
            // selection settles after a handle drag — avoids thrashing SwiftData
            // on every pixel of movement.
            if textView.selectedRange.length == 0, parent?.editingHighlightID == nil {
                activeHighlightID = nil
                activeColor = nil
            }
        }

        /// Forgets the session highlight, optionally collapsing the selection.
        private func endSession(collapseSelection: Bool) {
            activeHighlightID = nil
            activeColor = nil
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
            guard let onProgress = parent?.onScrollProgress else { return }
            let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
            let total = scrollView.contentSize.height
            guard total > 0 else { return }
            onProgress(min(1.0, max(0.0, Double(visibleBottom / total))))
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
final class ReaderTextView: UITextView {
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

    override func layoutSubviews() {
        super.layoutSubviews()
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

    private func applyReaderInsets() {
        let liveTop = safeAreaInsets.top
        if liveTop > 0 {
            immersiveTopInset = min(immersiveTopInset ?? liveTop, liveTop)
        }
        let frozenTop = immersiveTopInset ?? liveTop

        let desired = UIEdgeInsets(
            top: baseTextInsets.top + frozenTop,
            left: baseTextInsets.left,
            bottom: baseTextInsets.bottom + safeAreaInsets.bottom,
            right: baseTextInsets.right
        )
        if textContainerInset != desired {
            textContainerInset = desired
        }

        // Scroll indicators should still dodge the *live* bars, not the frozen
        // inset — the scrollbar tucking under the nav bar looks broken.
        let indicator = UIEdgeInsets(top: liveTop, left: 0, bottom: safeAreaInsets.bottom, right: 0)
        if verticalScrollIndicatorInsets != indicator {
            verticalScrollIndicatorInsets = indicator
        }
    }
}
