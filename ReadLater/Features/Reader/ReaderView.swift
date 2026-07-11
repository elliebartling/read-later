import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    let article: Article

    @State private var tts = TTSController()
    @State private var pendingNoteIntent: HighlightableTextView.HighlightIntent?
    @State private var showingTypographyControls = false

    private var settings: AppSettings {
        settingsRows.first ?? AppSettings()
    }

    private var paragraphs: [String] {
        article.plainText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var currentParagraphRange: NSRange? {
        guard tts.isPlaying, tts.currentParagraph < paragraphs.count else { return nil }
        let target = paragraphs[tts.currentParagraph]
        guard let range = article.plainText.range(of: target) else { return nil }
        return NSRange(range, in: article.plainText)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            settings.readerTheme.background.swiftUIColor
                .ignoresSafeArea()

            HighlightableTextView(
                text: article.plainText,
                highlights: article.highlights,
                currentSpokenRange: currentParagraphRange,
                theme: settings.readerTheme,
                fontSize: CGFloat(settings.readerFontSize),
                fontFamily: settings.readerFontFamily,
                onHighlight: handleIntent
            )
            .ignoresSafeArea(.container, edges: .bottom)

            if tts.totalParagraphs > 0 {
                TTSPlayerBar(controller: tts)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle(article.siteName ?? article.url.host ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if tts.isPlaying { tts.pause() } else { startTTS() }
                } label: {
                    Image(systemName: tts.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingTypographyControls = true
                    } label: {
                        Label("Typography", systemImage: "textformat.size")
                    }
                    Button {
                        exportToObsidian()
                    } label: {
                        Label("Export to Obsidian", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Link(destination: article.url) {
                        Label("Open Original", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if article.readAt == nil {
                article.readAt = .now
                try? context.save()
            }
        }
        .onDisappear { tts.stop() }
        .sheet(isPresented: $showingTypographyControls) {
            TypographyControls(settings: settings)
        }
        .sheet(item: $pendingNoteIntent) { intent in
            HighlightNoteSheet(intent: intent) { note in
                persistHighlight(intent: intent, note: note)
            }
        }
    }

    private func startTTS() {
        tts.start(
            paragraphs: paragraphs,
            provider: settings.ttsProvider,
            voice: settings.ttsVoice,
            startAt: tts.currentParagraph
        )
    }

    private func handleIntent(_ intent: HighlightableTextView.HighlightIntent) {
        if intent.requestsNote {
            pendingNoteIntent = intent
        } else {
            persistHighlight(intent: intent, note: nil)
        }
    }

    private func persistHighlight(intent: HighlightableTextView.HighlightIntent, note: String?) {
        let h = Highlight(
            article: article,
            startOffset: intent.startOffset,
            endOffset: intent.endOffset,
            quotedText: intent.quotedText,
            color: intent.color,
            note: note
        )
        context.insert(h)
        try? context.save()
        Task { exportToObsidian(silent: true) }
    }

    private func exportToObsidian(silent: Bool = false) {
        do {
            try ObsidianExporter.exportArticle(article, settings: settings)
        } catch {
            if !silent {
                NSLog("Obsidian export failed: %@", String(describing: error))
            }
        }
    }
}

extension HighlightableTextView.HighlightIntent: Identifiable {
    var id: String { "\(startOffset)-\(endOffset)-\(color.rawValue)" }
}

extension UIColor {
    var swiftUIColor: Color { Color(uiColor: self) }
}
