import UIKit

/// A `UITextView` that suppresses the system's blue selection wash while keeping
/// the drag handles and magnifier.
///
/// Selecting text in the reader creates a highlight instantly, so the yellow
/// highlight already marks the range — the blue tint on top of it just muddies
/// the color. The wash is drawn by the text view's
/// `UITextSelectionDisplayInteraction.highlightView`; UIKit re-shows it whenever
/// the selection re-activates, so `hideSelectionHighlight()` is re-applied from
/// `layoutSubviews` and callers should also re-apply it on every selection
/// change (`textViewDidChangeSelection`).
///
/// Both reader front-ends share this: the plain reader's `ReaderTextView`
/// subclasses it, and the block reader instantiates it directly.
class SelectionWashHidingTextView: UITextView {
    override func layoutSubviews() {
        super.layoutSubviews()
        hideSelectionHighlight()
    }

    /// Hides only the blue selection wash (`highlightView`), leaving the drag
    /// handles and magnifier untouched. Public API only —
    /// `UITextSelectionDisplayInteraction` is public.
    func hideSelectionHighlight() {
        if selectionDisplayInteraction == nil {
            selectionDisplayInteraction = Self.findSelectionDisplayInteraction(in: self)
        }
        selectionDisplayInteraction?.highlightView.isHidden = true
    }

    /// UIKit attaches the interaction to an internal subview, not necessarily
    /// the text view itself, so search the whole subtree (it's shallow).
    private static func findSelectionDisplayInteraction(in root: UIView) -> UITextSelectionDisplayInteraction? {
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeLast()
            for interaction in view.interactions {
                if let selection = interaction as? UITextSelectionDisplayInteraction {
                    return selection
                }
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private weak var selectionDisplayInteraction: UITextSelectionDisplayInteraction?
}
