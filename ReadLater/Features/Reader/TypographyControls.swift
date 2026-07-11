import SwiftUI
import SwiftData

struct TypographyControls: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let fontFamilies = ["New York", "Georgia", "San Francisco", "Iowan Old Style", "Palatino"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Font") {
                    Picker("Family", selection: $settings.readerFontFamily) {
                        ForEach(fontFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    Stepper("Size: \(Int(settings.readerFontSize))",
                            value: $settings.readerFontSize,
                            in: 14...28,
                            step: 1)
                }
                Section("Theme") {
                    Picker("Theme", selection: .init(
                        get: { settings.readerTheme },
                        set: { settings.readerTheme = $0 }
                    )) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Typography")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
