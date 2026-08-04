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
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    let onTapHighlight: (UUID) -> Void
    /// Plain single tap in the body (not a selection or highlight tap).
    var onTap: (() -> Void)? = nil

    var body: some View {
        quoted
            // **H5.** Reading position is machine state: a hueless wash derived
            // from this page's own paper, plus a leading `Accent.primary` rail.
            // It used to be a pale yellow band indistinguishable from a yellow
            // highlight (audit theme 7). The plain reader paints the identical
            // pair — the wash as a text attribute, the rail as a layer.
            .background(isSpoken ? Color(uiColor: spokenWash) : Color.clear)
            .overlay(alignment: .leading) {
                if isSpoken {
                    RoundedRectangle(
                        cornerRadius: SystemState.railWidth / 2,
                        style: .continuous
                    )
                    .fill(Color(uiColor: SystemState.railUI(darkBackground: theme.isDark)))
                    .frame(width: SystemState.railWidth)
                    .frame(maxHeight: .infinity)
                    // The rail sits in the page margin, outside the text
                    // column, the same place the plain reader puts it.
                    .offset(x: -(SystemState.railWidth + Self.railGap))
                    .accessibilityHidden(true)
                }
            }
    }

    /// Gap between the spoken rail and the text column's leading edge. Matches
    /// `ReaderTextView.railGap`.
    private static let railGap: CGFloat = 8

    private var spokenWash: UIColor {
        SystemState.washUI(overPaper: theme.background, darkBackground: theme.isDark)
    }

    /// Quote treatment, applied AROUND the per-type chrome so it composes with
    /// it: a multi-paragraph quote is several flagged blocks that each get the
    /// bar, and a quoted list item keeps its marker inside the bar. Keyed on
    /// `isQuoted` (the additive flag OR the legacy `.blockquote` type) rather
    /// than the type alone, which is what makes the flattened-quote fix visible
    /// here. The text tone is dropped to secondary in `foreground(for:)`.
    @ViewBuilder
    private var quoted: some View {
        if block.isQuoted {
            HStack(alignment: .top, spacing: Self.quoteGap) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(uiColor: theme.foreground).opacity(0.25))
                    .frame(width: Self.quoteBarWidth)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
                chrome
            }
            .padding(.leading, Self.quoteInset)
        } else {
            chrome
        }
    }

    /// Leading vertical quote bar, and the inset that sets the quote in from
    /// the body column. Sized against the code container's own padding scale
    /// so the two reader "containers" read as one family.
    private static let quoteBarWidth: CGFloat = 4
    private static let quoteGap: CGFloat = 12
    private static let quoteInset: CGFloat = 4

    /// Per-type SwiftUI layout wrapped around the selectable text.
    @ViewBuilder
    private var chrome: some View {
        switch block.type {
        case .listItem where block.markerBaked == true:
            // Marker is already inline in `block.text` (parse-time baking) — the
            // same text the plain reader renders. Lay it out as an ordinary
            // paragraph so the two readers match and the marker isn't doubled.
            representable
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

}

// MARK: - Block text view

/// The block reader's `UITextView`: hides the selection wash (super) and pins
/// the container to zero insets / zero line-fragment padding on EVERY layout
/// pass. The block's horizontal margins are SwiftUI padding around the view, so
/// any UIKit-side inset reappearing (e.g. a TextKit 1 compatibility fallback
/// swapping the text container restores the default 5pt padding) would shift
/// the text and stick until something else touched the container — the same
/// sticky-inset failure ReaderTextView heals per-pass in the plain reader.
final class BlockTextView: SelectionWashHidingTextView {
    override func layoutSubviews() {
        if textContainerInset != .zero {
            textContainerInset = .zero
        }
        if textContainer.lineFragmentPadding != 0 {
            textContainer.lineFragmentPadding = 0
        }
        super.layoutSubviews()
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
    let onDeleteHighlight: (UUID) -> Void
    let onRequestNote: (UUID) -> Void
    let onTapHighlight: (UUID) -> Void
    let onTap: (() -> Void)?

    /// UTF-16 length of this block's text storage.
    private var textLength: Int { ((block.text ?? "") as NSString).length }

    func makeUIView(context: Context) -> UITextView {
        // BlockTextView (a SelectionWashHidingTextView) hides the system's blue
        // selection wash so it doesn't paint over the instantly-created yellow
        // highlight, matching the plain reader's ReaderTextView — and re-pins
        // its zero container insets on every layout pass, mirroring
        // ReaderTextView's per-pass healing.
        let tv = BlockTextView()
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
        let codeSig = (block.codeRanges ?? []).map { $0.map(String.init).joined(separator: "-") }
            .joined(separator: ",")
        return "\(textLength)|\(block.type.rawValue)|\(block.level ?? 0)|\(block.isQuoted)|\(block.markerBaked == true)|\(theme.rawValue)|\(fontSize)|\(fontRaw)|\(lineSpacing)|\(highlightSig)|\(codeSig)"
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

        // **Hanging indent** (fix #4). A marker-baked list item renders its
        // "• " / "3. " inline, so without this its wrapped lines align under
        // the bullet and the item loses its shape. The plain reader applies the
        // same measured indent over the same marker — one number, two readers.
        let blockFont = font(for: block)
        if block.type == .listItem, block.markerBaked == true,
           let prefix = ArticleBlocks.bakedMarkerPrefix(text)
        {
            paragraphStyle.headIndent = ReaderTypography.markerWidth(prefix, font: blockFont)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: blockFont,
            .foregroundColor: foreground(for: block),
            .paragraphStyle: paragraphStyle,
        ]
        let str = NSMutableAttributedString(string: text, attributes: attrs)

        // **Inline code** (fix #4). Same face and same wash the plain reader
        // uses, and the same wash the block-level code panel is filled with.
        // Applied BEFORE highlights so a highlight over a snippet still wins.
        if let ranges = block.codeRanges, !ranges.isEmpty, block.type != .preformatted {
            let codeFont = ReaderTypography.inlineCodeFont(bodySize: fontSize)
            let wash = ReaderTypography.inlineCodeBackground(foreground: theme.foreground)
            let length = (text as NSString).length
            for pair in ranges {
                guard pair.count == 2, pair[0] >= 0, pair[1] > 0,
                      pair[0] + pair[1] <= length else { continue }
                str.addAttributes(
                    [.font: codeFont, .backgroundColor: wash],
                    range: NSRange(location: pair[0], length: pair[1])
                )
            }
        }

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

    /// Quoted text and captions render in a secondary tone. `isQuoted` covers
    /// both the legacy `.blockquote` type and the flag now set on every block
    /// inside a quote, so a multi-paragraph quote is uniformly toned.
    private func foreground(for block: ArticleBlock) -> UIColor {
        if block.isQuoted || block.type == .caption {
            return theme.foreground.withAlphaComponent(0.7)
        }
        return theme.foreground
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
                highlightID = id
            }

            // H1 — same move as the plain reader: the text-only colour list
            // is deleted and `Color` opens the edit sheet's swatch row, the
            // app's only picker. Keep the two menus identical.
            let color = UIAction(
                title: "Color"
            ) { [weak self] _ in
                self?.parent?.onTapHighlight(highlightID)
            }
            let addNote = UIAction(
                title: "Add note"
            ) { [weak self] _ in
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
            (textView as? SelectionWashHidingTextView)?.hideSelectionHighlight()
            guard !suppressSelectionChange else { return }
            // Selection collapsed: end the session unless sheet-edit mode is
            // holding the highlight open. Range updates happen in
            // editMenuForTextIn when a handle drag settles.
            if textView.selectedRange.length == 0, parent?.effectiveEditingID == nil {
                activeHighlightID = nil
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
            suppressSelectionChange = true
            tv.selectedRange = range
            suppressSelectionChange = false
            tv.scrollRangeToVisible(range)
        }

        /// Forgets the session highlight, optionally collapsing the selection.
        private func endSession(collapseSelection: Bool) {
            activeHighlightID = nil
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
