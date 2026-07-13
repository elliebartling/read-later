import SwiftUI
import UIKit

/// Renders ONE text-bearing `ArticleBlock` as a self-sizing, selectable
/// (non-scrolling) `UITextView`, mirroring `HighlightableTextView`'s proven
/// instant-highlight coordinator patterns but scoped to a single block.
///
/// Offset discipline: the text storage contains EXACTLY `block.text` (list
/// markers are composed in SwiftUI, never prefixed into storage), so a
/// selection's local UTF-16 range maps to a GLOBAL `plainText` offset by adding
/// `baseOffset`. Every callback speaks GLOBAL offsets; painting consumes
/// `locatedRanges` whose `NSRange`s are already LOCAL to this block (the parent
/// — Task 7 — does all `HighlightAnchor` location, keeping it in one place).
///
/// The spoken-block tint and per-type chrome (list marker, blockquote bar) are
/// composed OUTSIDE the representable in SwiftUI; the representable owns only
/// the text, its per-type typography, highlight painting, and selection.
struct TextBlockView: View {

    /// A highlight already located against this block, with a LOCAL range.
    struct LocatedHighlight: Equatable {
        let id: UUID
        let color: HighlightColor
        /// UTF-16 range LOCAL to `block.text` (parent shifted out `baseOffset`).
        let range: NSRange
    }

    let block: ArticleBlock
    /// UTF-16 offset of `block.text`'s start within the article's `plainText`.
    let baseOffset: Int
    /// Precomputed leading marker for `.listItem` blocks ("•" or "3.").
    /// Supplied by the parent (BlockReaderView, Task 7) — nil for non-list blocks.
    var listMarker: String? = nil
    /// Highlights intersecting this block, ranges already LOCAL to `block.text`.
    let locatedRanges: [LocatedHighlight]
    /// True when TTS is currently speaking this block (paints a spoken tint).
    var isSpoken: Bool = false
    let theme: ReaderTheme
    let fontSize: CGFloat
    let fontRaw: String
    let lineSpacing: CGFloat
    /// Color applied to instantly-created highlights (the last-used color).
    let defaultColor: HighlightColor
    /// When the matching highlight lives in THIS block, its range is kept
    /// selected so the system drag handles stay visible for in-place resizing.
    var editingHighlightID: UUID? = nil

    /// Same callback family as `HighlightableTextView`; ALL offsets are GLOBAL.
    let onCreateHighlight: (HighlightableTextView.HighlightIntent) -> UUID?
    let onUpdateHighlight: (UUID, NSRange, String) -> Void
    let onRecolorHighlight: (UUID, HighlightColor) -> Void
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    let onTapHighlight: (UUID) -> Void
    /// Plain single tap in the body (not a selection or highlight tap).
    var onTap: (() -> Void)? = nil

    var body: some View {
        chrome
            .background(isSpoken ? Color(uiColor: Self.spokenTint(darkBackground: theme.isDark)) : Color.clear)
    }

    /// Per-type SwiftUI layout wrapped around the selectable text.
    @ViewBuilder
    private var chrome: some View {
        switch block.type {
        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(listMarker ?? "•")
                    .font(Font(bodyFont as CTFont))
                    .foregroundColor(Color(uiColor: theme.foreground))
                    .accessibilityHidden(true)
                representable
                    // Report the first-line baseline so the marker aligns with
                    // the text baseline rather than the view's bottom edge.
                    .alignmentGuide(.firstTextBaseline) { _ in bodyFont.ascender }
            }
        case .blockquote:
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(uiColor: theme.foreground).opacity(0.25))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                representable
            }
        case .preformatted:
            codeBlock
        default:
            representable
        }
    }

    /// A `.preformatted` block as a distinct code container: a monospaced,
    /// whitespace-preserving text view that never wraps mid-token, hosted in a
    /// horizontal `ScrollView` so long lines scroll instead of reflowing, inside
    /// a subtle rounded, inset panel tinted from the reader theme.
    private var codeBlock: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            BlockTextRepresentable(
                block: block,
                baseOffset: baseOffset,
                locatedRanges: locatedRanges,
                theme: theme,
                fontSize: fontSize,
                fontRaw: fontRaw,
                lineSpacing: lineSpacing,
                defaultColor: defaultColor,
                editingHighlightID: editingHighlightID,
                wraps: false,
                onCreateHighlight: onCreateHighlight,
                onUpdateHighlight: onUpdateHighlight,
                onRecolorHighlight: onRecolorHighlight,
                onDeleteHighlight: onDeleteHighlight,
                onRequestNote: onRequestNote,
                onTapHighlight: onTapHighlight,
                onTap: onTap
            )
            .padding(.horizontal, Self.codePaddingH)
            .padding(.vertical, Self.codePaddingV)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: theme.foreground.withAlphaComponent(0.055)))
        .clipShape(RoundedRectangle(cornerRadius: Self.codeCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.codeCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: theme.foreground.withAlphaComponent(0.12)), lineWidth: 1)
        )
    }

    private static let codeCornerRadius: CGFloat = 10
    private static let codePaddingH: CGFloat = 14
    private static let codePaddingV: CGFloat = 12

    private var representable: some View {
        BlockTextRepresentable(
            block: block,
            baseOffset: baseOffset,
            locatedRanges: locatedRanges,
            theme: theme,
            fontSize: fontSize,
            fontRaw: fontRaw,
            lineSpacing: lineSpacing,
            defaultColor: defaultColor,
            editingHighlightID: editingHighlightID,
            wraps: true,
            onCreateHighlight: onCreateHighlight,
            onUpdateHighlight: onUpdateHighlight,
            onRecolorHighlight: onRecolorHighlight,
            onDeleteHighlight: onDeleteHighlight,
            onRequestNote: onRequestNote,
            onTapHighlight: onTapHighlight,
            onTap: onTap
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Body reader font at the current size — used for the SwiftUI list marker
    /// so its metrics match the block text.
    private var bodyFont: UIFont {
        (ReaderFont(rawValue: fontRaw) ?? .serif).uiFont(size: fontSize)
    }

    /// Spoken-paragraph tint — identical colors to the TextKit reader path.
    static func spokenTint(darkBackground: Bool) -> UIColor {
        darkBackground
            ? UIColor(white: 1, alpha: 0.14)
            : UIColor.systemYellow.withAlphaComponent(0.16)
    }
}

// MARK: - Representable

/// The selectable, self-sizing `UITextView` for a single block's text.
private struct BlockTextRepresentable: UIViewRepresentable {

    let block: ArticleBlock
    let baseOffset: Int
    let locatedRanges: [TextBlockView.LocatedHighlight]
    let theme: ReaderTheme
    let fontSize: CGFloat
    let fontRaw: String
    let lineSpacing: CGFloat
    let defaultColor: HighlightColor
    let editingHighlightID: UUID?
    /// When false, the text is laid out at its natural (unwrapped) width so a
    /// horizontal `ScrollView` can scroll long lines — used for `.preformatted`
    /// code blocks, where mid-token wrapping would mangle the content.
    var wraps: Bool = true

    let onCreateHighlight: (HighlightableTextView.HighlightIntent) -> UUID?
    let onUpdateHighlight: (UUID, NSRange, String) -> Void
    let onRecolorHighlight: (UUID, HighlightColor) -> Void
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    let onTapHighlight: (UUID) -> Void
    let onTap: (() -> Void)?

    /// UTF-16 length of this block's text storage.
    private var textLength: Int { ((block.text ?? "") as NSString).length }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        // Non-scrolling: SwiftUI (via sizeThatFits) owns the height; the parent
        // ScrollView owns scrolling.
        tv.isScrollEnabled = false
        tv.dataDetectorTypes = [.link]
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.adjustsFontForContentSizeCategory = false
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        context.coordinator.parent = self

        // Single tap toggles chrome / hits a highlight. cancelsTouchesInView =
        // false + simultaneous recognition keep the text view's own selection
        // gestures intact.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self

        let signature = renderSignature()
        if signature != context.coordinator.lastRenderSignature {
            let preserved = tv.selectedRange
            // Re-rendering resets the selection; suppress the delegate callback
            // so the transient reset doesn't end an in-progress highlight session.
            context.coordinator.suppressSelectionChange = true
            tv.attributedText = render()
            if preserved.location + preserved.length <= (tv.text as NSString).length {
                tv.selectedRange = preserved
            }
            context.coordinator.suppressSelectionChange = false
            context.coordinator.lastRenderSignature = signature
        }

        context.coordinator.applyEditingSelectionIfNeeded()
    }

    // iOS 16+ self-sizing: measure the text within the proposed width so the
    // block reports its natural height to SwiftUI.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        // Code blocks: report the natural UNWRAPPED size (widest line × height)
        // regardless of the proposal — the enclosing horizontal ScrollView owns
        // scrolling, and a proposal width would force reflow we don't want.
        if !wraps {
            let fitted = tv.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: ceil(fitted.width), height: ceil(fitted.height))
        }
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fitted = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Only the highlight this block actually contains counts as "being edited"
    /// here — the parent shares one `editingHighlightID` across every block.
    private var effectiveEditingID: UUID? {
        guard let id = editingHighlightID,
              locatedRanges.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func renderSignature() -> String {
        let highlightSig = locatedRanges
            .map { "\($0.id.uuidString):\($0.range.location):\($0.range.length):\($0.color.rawValue)" }
            .joined(separator: "|")
        return "\(textLength)|\(block.type.rawValue)|\(block.level ?? 0)|\(theme.rawValue)|\(fontSize)|\(fontRaw)|\(lineSpacing)|\(highlightSig)"
    }

    // MARK: - Rendering

    private func render() -> NSAttributedString {
        let text = block.text ?? ""
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        switch block.type {
        case .caption:
            paragraphStyle.alignment = .center
        case .preformatted:
            // Code never breaks mid-token: whole lines stay intact and the
            // enclosing horizontal ScrollView scrolls anything wider than the
            // column. Word wrapping only ever applies as a last resort if the
            // block is somehow constrained below its natural width.
            paragraphStyle.lineBreakMode = .byWordWrapping
        default:
            break
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: block),
            .foregroundColor: foreground(for: block.type),
            .paragraphStyle: paragraphStyle,
        ]
        let str = NSMutableAttributedString(string: text, attributes: attrs)

        let darkBackground = theme.isDark
        let length = (text as NSString).length
        for located in locatedRanges {
            let r = located.range
            guard r.location >= 0, r.length > 0, r.location + r.length <= length else { continue }
            str.addAttribute(.backgroundColor,
                             value: located.color.uiColor(darkBackground: darkBackground),
                             range: r)
        }
        return str
    }

    private func font(for block: ArticleBlock) -> UIFont {
        let base = (ReaderFont(rawValue: fontRaw) ?? .serif).uiFont(size: fontSize)
        switch block.type {
        case .heading:
            let scale: CGFloat
            switch block.level ?? 2 {
            case 1: scale = 1.6
            case 2: scale = 1.4
            case 3: scale = 1.25
            default: scale = 1.15
            }
            let scaled = (ReaderFont(rawValue: fontRaw) ?? .serif).uiFont(size: fontSize * scale)
            if let bold = scaled.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: bold, size: scaled.pointSize)
            }
            return scaled
        case .preformatted:
            // Slightly smaller than body so more code fits per line, but still
            // scaled by the reader's typography setting.
            return .monospacedSystemFont(ofSize: fontSize * 0.88, weight: .regular)
        case .caption:
            return base.withSize(fontSize * 0.85)
        default:
            return base
        }
    }

    private func foreground(for type: BlockType) -> UIColor {
        switch type {
        case .blockquote, .caption:
            return theme.foreground.withAlphaComponent(0.7)
        default:
            return theme.foreground
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var textView: UITextView?
        var parent: BlockTextRepresentable?
        var lastRenderSignature: String = ""
        /// Set while updateUIView programmatically resets/restores the selection.
        var suppressSelectionChange = false

        /// The highlight created by the current selection "session"; handle drags
        /// update it instead of stacking duplicates. Ends when the selection
        /// collapses (unless sheet-edit mode holds it open).
        private var activeHighlightID: UUID?
        private var activeColor: HighlightColor?
        /// Last `effectiveEditingID` we applied a selection for — avoids
        /// re-selecting on every SwiftUI tick while the sheet is open.
        private var appliedEditingHighlightID: UUID?

        // MARK: Instant highlight (mirrors HighlightableTextView)

        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let parent = parent,
                  let text = parent.block.text,
                  let swiftRange = Range(range, in: text) else {
                return UIMenu(children: suggestedActions)
            }
            let quoted = String(text[swiftRange])
            let base = parent.baseOffset
            let globalRange = NSRange(location: range.location + base, length: range.length)

            // Sheet-edit mode: the sheet owns the session. When the edited
            // highlight lives in THIS block, a settled selection resizes it.
            // When it lives in ANOTHER block, do nothing — creating a fresh
            // highlight mid-edit would silently mint a duplicate.
            if parent.editingHighlightID != nil {
                guard let editingID = parent.effectiveEditingID else {
                    return UIMenu(children: suggestedActions)
                }
                activeHighlightID = editingID
                parent.onUpdateHighlight(editingID, globalRange, quoted)
                return UIMenu(children: suggestedActions)
            }

            let highlightID: UUID
            if let active = activeHighlightID {
                parent.onUpdateHighlight(active, globalRange, quoted)
                highlightID = active
            } else {
                let intent = HighlightableTextView.HighlightIntent(
                    startOffset: range.location + base,
                    endOffset: range.location + range.length + base,
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
            // holding the highlight open. Range updates happen in
            // editMenuForTextIn when a handle drag settles.
            if textView.selectedRange.length == 0, parent?.effectiveEditingID == nil {
                activeHighlightID = nil
                activeColor = nil
            }
        }

        /// Selects the edited highlight's range so drag handles appear, or
        /// collapses the selection when sheet-edit mode ends.
        func applyEditingSelectionIfNeeded() {
            guard let parent = parent, let tv = textView else { return }
            let editingID = parent.effectiveEditingID
            guard editingID != appliedEditingHighlightID else { return }
            appliedEditingHighlightID = editingID

            guard let id = editingID,
                  let located = parent.locatedRanges.first(where: { $0.id == id }) else {
                if editingID == nil, activeHighlightID != nil || tv.selectedRange.length > 0 {
                    endSession(collapseSelection: true)
                }
                return
            }

            let range = located.range
            guard range.location >= 0,
                  range.location + range.length <= (tv.text as NSString).length else { return }
            activeHighlightID = id
            activeColor = located.color
            suppressSelectionChange = true
            tv.selectedRange = range
            suppressSelectionChange = false
            tv.scrollRangeToVisible(range)
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

        // MARK: Tap handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let tv = textView, let parent = parent else { return }
            // A tap on an active selection is meant for the text view (dismiss).
            if tv.selectedRange.length > 0 { return }
            let point = gesture.location(in: tv)
            if isLink(at: point, in: tv) { return }
            if let id = highlightID(at: point, in: tv, parent: parent) {
                parent.onTapHighlight(id)
                return
            }
            parent.onTap?()
        }

        /// True if `point` falls on a `.link`-attributed glyph.
        private func isLink(at point: CGPoint, in tv: UITextView) -> Bool {
            guard let index = characterIndex(at: point, in: tv) else { return false }
            guard let attributed = tv.attributedText, index < attributed.length else { return false }
            return attributed.attribute(.link, at: index, effectiveRange: nil) != nil
        }

        /// ID of the located highlight whose LOCAL range contains `point`.
        private func highlightID(at point: CGPoint, in tv: UITextView,
                                 parent: BlockTextRepresentable) -> UUID? {
            guard !parent.locatedRanges.isEmpty,
                  let index = characterIndex(at: point, in: tv) else { return nil }
            for located in parent.locatedRanges {
                let r = located.range
                if index >= r.location, index < r.location + r.length {
                    return located.id
                }
            }
            return nil
        }

        /// Character index at `point` via UITextInput geometry (stays on TextKit
        /// 2 — never touches layoutManager/textStorage, matching the TextKit path).
        private func characterIndex(at point: CGPoint, in tv: UITextView) -> Int? {
            let length = (tv.text as NSString).length
            guard length > 0, let position = tv.closestPosition(to: point) else { return nil }
            let index = tv.offset(from: tv.beginningOfDocument, to: position)
            guard index >= 0, index < length else { return nil }
            // closestPosition snaps to the nearest glyph even in the margins;
            // confirm the tap is actually on that line so blank taps toggle chrome.
            let caret = tv.caretRect(for: position)
            guard caret.minY.isFinite, caret.height > 0,
                  point.y >= caret.minY - 4, point.y <= caret.maxY + 4 else { return nil }
            return index
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
