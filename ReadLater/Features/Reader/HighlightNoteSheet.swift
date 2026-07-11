import SwiftUI

struct HighlightNoteSheet: View {
    let intent: HighlightableTextView.HighlightIntent
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Quoted") {
                    Text(intent.quotedText)
                        .font(.body)
                        .lineLimit(6)
                }
                Section("Note") {
                    TextField("Why does this matter?", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onSave(nil); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note.isEmpty ? nil : note)
                        dismiss()
                    }
                }
            }
        }
    }
}
