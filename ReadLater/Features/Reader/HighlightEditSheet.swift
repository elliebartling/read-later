import SwiftUI
import SwiftData

/// Edits a persisted highlight: color, note, delete. Presented both right
/// after an instant highlight ("Add Note" in the selection menu) and when the
/// user taps an existing highlight in the reader.
///
/// **SH5 — an editor sheet shows the thing it edits.** The passage leads the
/// sheet, carrying its own marker rail in the highlight's colour (the H2
/// grammar the Highlights list uses), so recolouring is visibly a change *to
/// this passage* rather than an abstract swatch pick. It used to be absent on
/// the reasoning that the reader behind the medium detent still shows the
/// selection — true, and exactly the argument SH5 exists to overrule: the
/// keyboard covers that reader the moment you tap the note field.
///
/// The reader keeps the selection handles on the highlight so the range can
/// still be adjusted in place. Changes are written to the model as they happen
/// so the reader updates live; the presenting view saves the context and
/// re-exports on dismiss. Deletion is deferred to the presenter via `onDelete`
/// so this sheet never renders a deleted model.
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

    /// **SH5 / H2.** The passage, with the marker-colour rail the Highlights
    /// list uses — the one rail the constitution kept when R1's row rail was
    /// struck, because it sits *inside* its card and encodes the marker colour,
    /// which nothing else does.
    private var passage: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: Self.railWidth / 2, style: .continuous)
                .fill(highlight.color.marker)
                .frame(width: Self.railWidth)
                .frame(maxHeight: .infinity)
                // §10 Micro — recolouring a rail is a tint change.
                .motionMicro(value: highlight.color)
                .accessibilityHidden(true)
            Text(highlight.quotedText)
                .font(.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Highlighted passage: \(highlight.quotedText)")
    }

    /// H2 — 4pt, full height.
    private static let railWidth: CGFloat = 4

    var body: some View {
        NavigationStack {
            Form {
                // SH5 — the thing being edited, first.
                Section {
                    passage
                }
                Section("Colour") {
                    // H1 — the one swatch component. This sheet is now the
                    // app's only highlight-colour picker; the reader's
                    // text-list menu was deleted in wave 3 and routes here.
                    HighlightSwatchRow(
                        selection: Binding(
                            get: { highlight.color },
                            set: { highlight.color = $0 }
                        ),
                        onPick: { colour in
                            lastHighlightColorRaw = colour.rawValue
                            // M4 — `.selection` on highlight-colour change. One
                            // of exactly two legal haptics in the app.
                            Haptic.selection()
                        }
                    )
                }
                Section("Note") {
                    TextField("Why does this matter?", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($noteFocused)
                }
                Section {
                    // T7 — sentence case.
                    FormRowButton(title: "Remove highlight", isDestructive: true) {
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
