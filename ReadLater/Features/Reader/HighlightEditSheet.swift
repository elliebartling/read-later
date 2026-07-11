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
                    HStack(spacing: 18) {
                        ForEach(HighlightColor.allCases) { color in
                            Button {
                                highlight.color = color
                                lastHighlightColorRaw = color.rawValue
                            } label: {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if highlight.color == color {
                                            Image(systemName: "checkmark")
                                                .font(.footnote.weight(.bold))
                                                .foregroundStyle(.black.opacity(0.6))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.displayName)
                            .accessibilityAddTraits(highlight.color == color ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
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
