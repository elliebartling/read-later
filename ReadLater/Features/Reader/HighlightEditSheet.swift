import SwiftUI
import SwiftData

/// Edits a persisted highlight: color, note, delete. Presented both right
/// after an instant highlight ("Add Note" in the selection menu) and when the
/// user taps an existing highlight in the reader.
///
/// The quoted text is *not* shown here — the reader keeps the selection
/// handles on the highlight so the range can be adjusted in place. Changes
/// are written to the model as they happen so the reader (visible behind the
/// medium detent) updates live; the presenting view saves the context and
/// re-exports on dismiss. Deletion is deferred to the presenter via
/// `onDelete` so this sheet never renders a deleted model.
struct HighlightEditSheet: View {
    @Bindable var highlight: Highlight
    /// When true (Add Note), the note field becomes first responder on appear.
    var focusNoteOnAppear: Bool = false
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastHighlightColor") private var lastHighlightColorRaw = HighlightColor.yellow.rawValue
    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(highlight: Highlight, focusNoteOnAppear: Bool = false, onDelete: @escaping () -> Void) {
        self.highlight = highlight
        self.focusNoteOnAppear = focusNoteOnAppear
        self.onDelete = onDelete
        _note = State(initialValue: highlight.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Color") {
                    // H1 — the one swatch component. This sheet is now the
                    // app's only highlight-colour picker; the reader's
                    // text-list menu was deleted in wave 3 and routes here.
                    HighlightSwatchRow(
                        selection: Binding(
                            get: { highlight.color },
                            set: { highlight.color = $0 }
                        ),
                        onPick: { lastHighlightColorRaw = $0.rawValue }
                    )
                }
                Section("Note") {
                    TextField("Why does this matter?", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($noteFocused)
                }
                Section {
                    Button("Remove Highlight", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .pageForm()
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Written on every keystroke (not just Done) so a swipe-dismiss
            // still keeps the note.
            .onChange(of: note) { _, newValue in
                highlight.note = newValue.isEmpty ? nil : newValue
            }
            .onAppear {
                guard focusNoteOnAppear else { return }
                // Defer one run-loop tick so the sheet's TextField is in the
                // hierarchy before we ask for first-responder.
                DispatchQueue.main.async { noteFocused = true }
            }
        }
    }
}
