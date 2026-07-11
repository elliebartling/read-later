import SwiftUI
import SwiftData

/// Lightweight sheet behind the reader's bottom-bar tag button: toggle
/// existing tags on the article or create a new one inline.
struct TagAssignmentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    let article: Article

    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $newTagName)
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(trimmedNewTagName.isEmpty)
                    }
                }

                if !allTags.isEmpty {
                    Section("Tags") {
                        ForEach(allTags) { tag in
                            Button {
                                toggle(tag)
                            } label: {
                                HStack {
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if isAssigned(tag) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedNewTagName: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAssigned(_ tag: Tag) -> Bool {
        article.allTags.contains { $0.id == tag.id }
    }

    private func toggle(_ tag: Tag) {
        var tags = article.tags ?? []
        if let idx = tags.firstIndex(where: { $0.id == tag.id }) {
            tags.remove(at: idx)
        } else {
            tags.append(tag)
        }
        article.tags = tags
        try? context.save()
    }

    private func addTag() {
        let name = trimmedNewTagName
        guard !name.isEmpty else { return }
        newTagName = ""
        // Reuse an existing tag with the same name instead of duplicating it.
        if let existing = allTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !isAssigned(existing) { toggle(existing) }
            return
        }
        let tag = Tag(name: name)
        context.insert(tag)
        article.tags = (article.tags ?? []) + [tag]
        try? context.save()
    }
}
