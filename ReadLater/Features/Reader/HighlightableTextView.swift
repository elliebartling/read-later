import SwiftUI
import UIKit

/// SwiftUI wrapper around UITextView that:
/// 1. Renders `plainText` with existing highlights painted in place.
/// 2. Extends the system text-selection edit menu with "Highlight" (4 colors)
///    and "Highlight + Note" via the supported UITextViewDelegate hook
///    `textView(_:editMenuForTextIn:suggestedActions:)`. (Do NOT attach a
///    separate UIEditMenuInteraction — UITextView owns its edit menu and never
///    consults an extra interaction, so custom items would simply never show.)
/// 3. Emits a `HighlightIntent` when the user picks a color, so the ReaderView
///    can persist a Highlight into SwiftData.
/// 4. Reports scroll progress (0...1) so the reader can mark articles read
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
        let requestsNote: Bool
    }

    let text: String
    let highlights: [Highlight]
    let currentSpokenRange: NSRange?
    let theme: ReaderTheme
    let fontSize: CGFloat
    let fontRaw: String
    let onHighlight: (HighlightIntent) -> Void
    var onScrollProgress: ((Double) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.dataDetectorTypes = [.link]
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 40, right: 20)
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        context.coordinator.parent = self
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let signature = renderSignature()
        if signature != context.coordinator.lastRenderSignature {
            let preservedSelection = tv.selectedRange
            tv.attributedText = render()
            // Restore selection if it still fits — protects an in-progress highlight
            // from being wiped by unrelated SwiftUI updates (e.g. TTS paragraph advance).
            if preservedSelection.location + preservedSelection.length <= (tv.text as NSString).length {
                tv.selectedRange = preservedSelection
            }
            context.coordinator.lastRenderSignature = signature
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

    private func renderSignature() -> String {
        let highlightSig = highlights
            .map { "\($0.id.uuidString):\($0.startOffset):\($0.endOffset):\($0.colorRaw)" }
            .joined(separator: "|")
        let spoken = currentSpokenRange.map { "\($0.location)-\($0.length)" } ?? ""
        return "\(text.utf16.count)|\(theme.rawValue)|\(fontSize)|\(fontRaw)|\(highlightSig)|\(spoken)"
    }

    // MARK: - Rendering

    private func render() -> NSAttributedString {
        let font = (ReaderFont(rawValue: fontRaw) ?? .serif).uiFont(size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 12

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.foreground,
            .paragraphStyle: paragraphStyle,
        ]
        let str = NSMutableAttributedString(string: text, attributes: attrs)

        for h in highlights {
            if let located = HighlightAnchor.locate(
                in: text,
                startOffset: h.startOffset,
                endOffset: h.endOffset,
                quotedText: h.quotedText
            ) {
                let nsRange = NSRange(located.range, in: text)
                str.addAttribute(.backgroundColor, value: h.color.uiColor.withAlphaComponent(0.55), range: nsRange)
            }
        }

        if let range = currentSpokenRange, range.location + range.length <= (text as NSString).length {
            str.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.15), range: range)
        }
        return str
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        weak var textView: UITextView?
        var parent: HighlightableTextView?
        var lastRenderSignature: String = ""
        var lastSpokenLocation: Int?

        /// Scrolls so the spoken paragraph stays visible while TTS advances,
        /// without hijacking the view when the user is reading elsewhere.
        func scrollToKeepVisible(range: NSRange, in tv: UITextView) {
            // Never fight the user's finger.
            guard !tv.isTracking, !tv.isDragging, !tv.isDecelerating else { return }
            guard range.location + range.length <= (tv.text as NSString).length else { return }

            tv.layoutManager.ensureLayout(forCharacterRange: range)
            let glyphRange = tv.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = tv.layoutManager.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
            rect.origin.y += tv.textContainerInset.top

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

        // The supported customization point for a UITextView's selection menu.
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }

            let colorActions = HighlightColor.allCases.map { color in
                UIAction(title: color.displayName) { [weak self] _ in
                    self?.applyHighlight(range: range, color: color, requestsNote: false)
                }
            }
            let highlightMenu = UIMenu(
                title: "Highlight",
                image: UIImage(systemName: "highlighter"),
                children: colorActions
            )
            let addNote = UIAction(
                title: "Highlight + Note",
                image: UIImage(systemName: "note.text.badge.plus")
            ) { [weak self] _ in
                self?.applyHighlight(range: range, color: .yellow, requestsNote: true)
            }
            return UIMenu(children: [highlightMenu, addNote] + suggestedActions)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let onProgress = parent?.onScrollProgress else { return }
            let visibleBottom = scrollView.contentOffset.y + scrollView.bounds.height
            let total = scrollView.contentSize.height
            guard total > 0 else { return }
            onProgress(min(1.0, max(0.0, Double(visibleBottom / total))))
        }

        private func applyHighlight(range: NSRange, color: HighlightColor, requestsNote: Bool) {
            guard let tv = textView, let parent = parent else { return }
            guard range.length > 0, let swiftRange = Range(range, in: parent.text) else { return }
            let quoted = String(parent.text[swiftRange])
            let intent = HighlightableTextView.HighlightIntent(
                startOffset: range.location,
                endOffset: range.location + range.length,
                quotedText: quoted,
                color: color,
                requestsNote: requestsNote
            )
            parent.onHighlight(intent)
            tv.selectedRange = NSRange(location: range.location + range.length, length: 0)
        }
    }
}

extension ReaderTheme {
    var foreground: UIColor {
        switch self {
        case .light:  return UIColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1)
        case .dark:   return UIColor(white: 0.92, alpha: 1)
        case .sepia:  return UIColor(red: 0.35, green: 0.24, blue: 0.14, alpha: 1)
        case .system: return .label
        }
    }
    var background: UIColor {
        switch self {
        case .light:  return UIColor(white: 0.99, alpha: 1)
        case .dark:   return UIColor(white: 0.06, alpha: 1)
        case .sepia:  return UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1)
        case .system: return .systemBackground
        }
    }
}
