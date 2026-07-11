import SwiftUI
import UIKit

/// SwiftUI wrapper around UITextView that:
/// 1. Renders `plainText` with existing highlights painted in place.
/// 2. Presents a custom edit menu with "Highlight" (4 colors) + "Highlight + Note"
///    when the user has an active selection.
/// 3. Emits a `HighlightIntent` when the user picks a color, so the ReaderView
///    can persist a Highlight into SwiftData.
///
/// The current paragraph (spoken by TTS) can also be tinted by supplying
/// `currentParagraphRange` — the reader passes the offset range for the
/// paragraph currently playing.
struct HighlightableTextView: UIViewRepresentable {

    struct HighlightIntent: Equatable {
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
    let fontFamily: String
    let onHighlight: (HighlightIntent) -> Void

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
        installEditMenu(on: tv, coordinator: context.coordinator)
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
            if preservedSelection.location + preservedSelection.length <= tv.text.count {
                tv.selectedRange = preservedSelection
            }
            context.coordinator.lastRenderSignature = signature
        }
    }

    private func renderSignature() -> String {
        let highlightSig = highlights
            .map { "\($0.id.uuidString):\($0.startOffset):\($0.endOffset):\($0.colorRaw)" }
            .joined(separator: "|")
        let spoken = currentSpokenRange.map { "\($0.location)-\($0.length)" } ?? ""
        return "\(text.count)|\(theme.rawValue)|\(fontSize)|\(fontFamily)|\(highlightSig)|\(spoken)"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Rendering

    private func render() -> NSAttributedString {
        let font = UIFont(name: fontFamily, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 12

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.foreground,
            .paragraphStyle: paragraphStyle,
        ]
        let str = NSMutableAttributedString(string: text, attributes: attrs)

        // Apply saved highlights.
        let full = text
        for h in highlights {
            if let located = HighlightAnchor.locate(
                in: full,
                startOffset: h.startOffset,
                endOffset: h.endOffset,
                quotedText: h.quotedText
            ) {
                let nsRange = NSRange(located.range, in: full)
                str.addAttribute(.backgroundColor, value: h.color.uiColor.withAlphaComponent(0.55), range: nsRange)
            }
        }

        // Tint the paragraph currently being spoken.
        if let range = currentSpokenRange {
            str.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.15), range: range)
        }
        return str
    }

    // MARK: - Custom edit menu

    private func installEditMenu(on tv: UITextView, coordinator: Coordinator) {
        let interaction = UIEditMenuInteraction(delegate: coordinator)
        tv.addInteraction(interaction)
        coordinator.editMenuInteraction = interaction
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate {
        weak var textView: UITextView?
        weak var editMenuInteraction: UIEditMenuInteraction?
        var parent: HighlightableTextView?
        var lastRenderSignature: String = ""

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            let colorActions = HighlightColor.allCases.map { color in
                UIAction(title: color.displayName) { [weak self] _ in
                    self?.applyHighlight(color: color, requestsNote: false)
                }
            }
            let highlightMenu = UIMenu(title: "Highlight", image: UIImage(systemName: "highlighter"), children: colorActions)
            let addNote = UIAction(title: "Highlight + Note", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in
                self?.applyHighlight(color: .yellow, requestsNote: true)
            }
            var elements: [UIMenuElement] = [highlightMenu, addNote]
            elements.append(contentsOf: suggestedActions)
            return UIMenu(children: elements)
        }

        private func applyHighlight(color: HighlightColor, requestsNote: Bool) {
            guard let tv = textView, let parent = parent else { return }
            let range = tv.selectedRange
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
