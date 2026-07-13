import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query private var settingsRows: [AppSettings]
    let article: Article

    @State private var tts = TTSController()
    @State private var editingHighlight: Highlight?
    /// When true, the edit sheet focuses the note field on appear (Add Note).
    @State private var focusNoteOnAppear = false
    /// Deletion requested from the edit sheet — performed after the sheet
    /// dismisses so the sheet never renders a deleted model.
    @State private var pendingDeleteID: UUID?
    @State private var showingTypographyControls = false
    @State private var showingTagSheet = false
    /// Immersive reading: the top chrome starts hidden and a tap toggles it.
    @State private var chromeVisible = false
    /// Scroll position as a 0...1 fraction, kept minute-granular via
    /// `readingMinutesLeft` so scrolling doesn't spam view updates.
    @State private var readingMinutesLeft: Int?
    /// UTF-16 index of the character at the top of the viewport, updated while
    /// reading and written back to the article on disappear so reopening resumes
    /// at the same word instead of jumping to the top.
    @State private var latestTopOffset: Int?

    /// Color for instantly-created highlights; updated whenever the user picks
    /// a color, so new highlights reuse the last choice.
    @AppStorage("lastHighlightColor") private var lastHighlightColorRaw = HighlightColor.yellow.rawValue

    private var lastHighlightColor: HighlightColor {
        HighlightColor(rawValue: lastHighlightColorRaw) ?? .yellow
    }

    /// Chrome is forced visible outside the ready reading state so the user
    /// always has a back button while an article is parsing or has failed.
    private var showChrome: Bool {
        chromeVisible || article.parseStatus != .ready
    }

    /// One spring for every chrome reveal/dismiss so the two directions match.
    private static let chromeAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.85)

    // A row is seeded at startup (RootView); the transient fallback only
    // covers the first render tick and is never inserted or written to.
    private var settings: AppSettings {
        settingsRows.first ?? AppSettings()
    }

    /// Concrete palette for the current appearance mode + OS color scheme.
    private var resolvedTheme: ReaderTheme {
        settings.resolvedReaderTheme(systemIsDark: colorScheme == .dark)
    }

    private var paragraphs: [String] {
        article.plainText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var currentParagraphRange: NSRange? {
        guard tts.isActive, tts.currentParagraph < paragraphs.count else { return nil }
        let target = paragraphs[tts.currentParagraph]
        guard let range = article.plainText.range(of: target) else { return nil }
        return NSRange(range, in: article.plainText)
    }

    /// "XX minutes left" — listening time while the player is up, reading
    /// time otherwise.
    private var subtitleText: String {
        if tts.isActive {
            return ListeningTime.remainingLabel(seconds: tts.remainingSeconds)
        }
        let total = article.estimatedReadingMinutes
        guard total > 0 else { return article.siteName ?? article.url?.host ?? "" }
        let left = readingMinutesLeft ?? total
        return left < 1 ? "Less than a minute left" : "\(left) min left"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            resolvedTheme.background.swiftUIColor
                .ignoresSafeArea()

            readerContent
                // Keep the text view full-screen under both bars so its frame
                // never moves when the chrome appears. ReaderTextView then pins
                // the text with a frozen inset, so revealing the nav bar has no
                // effect on where the article sits — the bar just overlays it.
                .ignoresSafeArea(.container, edges: .vertical)

            floatingPlayer
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: tts.isActive)
        .readerTitleBar(title: article.title, subtitle: subtitleText)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
        .statusBarHidden(!showChrome)
        .toolbar(.hidden, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingTypographyControls = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Typography")
            }
        }
        .onDisappear {
            tts.stop()
            saveReadingProgress()
        }
        .sheet(isPresented: $showingTypographyControls) {
            TypographyControls(settings: settings, controller: tts)
        }
        .sheet(isPresented: $showingTagSheet) {
            TagAssignmentSheet(article: article)
        }
        .sheet(item: $editingHighlight, onDismiss: finishHighlightEditing) { highlight in
            HighlightEditSheet(
                highlight: highlight,
                focusNoteOnAppear: focusNoteOnAppear
            ) {
                pendingDeleteID = highlight.id
            }
            .presentationDetents([.medium, .large])
            // Let the user drag selection handles in the reader behind the sheet.
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .alert(
            "Couldn't read aloud",
            isPresented: Binding(
                get: { tts.lastError != nil },
                set: { if !$0 { tts.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tts.lastError ?? "")
        }
    }

    /// The floating pink capsule: the playing bar while read-aloud is active,
    /// the idle overflow/share/tag/play bar when chrome is up, and nothing in
    /// immersive reading. The two states cross-fade as one reshaping object.
    @ViewBuilder
    private var floatingPlayer: some View {
        Group {
            if tts.isActive {
                AudioPlayerBar(controller: tts, settings: settings)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.85, anchor: .bottom))
                    )
            } else if showChrome {
                IdlePlayerBar(
                    article: article,
                    onTags: { showingTagSheet = true },
                    onPlay: startTTS,
                    onExport: { exportToObsidian() },
                    onToggleRead: toggleRead
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var readerContent: some View {
        switch article.parseStatus {
        case .pending:
            parsingState
        case .failed:
            failedState
        case .ready:
            HighlightableTextView(
                text: article.plainText,
                highlights: article.allHighlights,
                currentSpokenRange: currentParagraphRange,
                theme: resolvedTheme,
                fontSize: CGFloat(settings.readerFontSize),
                fontRaw: settings.readerFontRaw,
                lineSpacing: CGFloat(settings.readerLineSpacing),
                paragraphSpacing: CGFloat(settings.readerParagraphSpacing),
                width: settings.readerWidth,
                defaultColor: lastHighlightColor,
                editingHighlightID: editingHighlight?.id,
                onCreateHighlight: createHighlight,
                onUpdateHighlight: updateHighlight,
                onRecolorHighlight: recolorHighlight,
                onDeleteHighlight: deleteHighlight,
                onRequestNote: { id in
                    focusNoteOnAppear = true
                    editingHighlight = findHighlight(id)
                },
                onTapHighlight: { id in
                    focusNoteOnAppear = false
                    editingHighlight = findHighlight(id)
                },
                onScrollProgress: handleScrollProgress,
                onTopCharacterOffset: { latestTopOffset = $0 },
                initialCharacterOffset: article.readingCharacterOffset,
                onTap: {
                    // Drive the chrome from a single explicit animation so both
                    // directions match. A redundant implicit `.animation(value:)`
                    // modifier used to fight this and left the *dismiss* un-animated.
                    withAnimation(Self.chromeAnimation) {
                        chromeVisible.toggle()
                    }
                }
            )
        }
    }

    private var parsingState: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("Extracting article…")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let host = article.url?.host {
                Text(host)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("Couldn't parse this page", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The extractor didn't find readable content on \(article.url?.host ?? "this page").")
        } actions: {
            if let url = article.url {
                Link(destination: url) { Text("Open in Safari") }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func startTTS() {
        // Keep the title / "X min left" nav chrome visible while listening.
        withAnimation(Self.chromeAnimation) { chromeVisible = true }
        let voice = settings.ttsProvider == .apple ? settings.appleVoiceID : settings.openAIVoice
        tts.start(
            paragraphs: paragraphs,
            provider: settings.ttsProvider,
            voice: voice,
            rate: settings.ttsRate,
            title: article.title,
            artist: article.siteName ?? article.url?.host,
            startAt: tts.currentParagraph
        )
    }

    /// GoodLinks-style read tracking: an article counts as read when the user
    /// actually reaches (nearly) the end, not when they merely open it.
    /// Also feeds the "X min left" subtitle.
    private func handleScrollProgress(_ progress: Double) {
        let total = article.estimatedReadingMinutes
        if total > 0 {
            let left = Int((Double(total) * (1 - progress)).rounded())
            if left != readingMinutesLeft {
                readingMinutesLeft = left
            }
        }
        guard progress >= 0.9, article.readAt == nil else { return }
        article.readAt = .now
        try? context.save()
    }

    /// Persists the top-of-viewport character offset when leaving the reader.
    /// Written once on disappear rather than on every scroll tick to avoid churn.
    private func saveReadingProgress() {
        guard let offset = latestTopOffset, offset != article.readingCharacterOffset else { return }
        article.readingCharacterOffset = offset
        try? context.save()
    }

    private func toggleRead() {
        article.readAt = article.readAt == nil ? .now : nil
        try? context.save()
    }

    // MARK: - Highlight actions

    private func findHighlight(_ id: UUID) -> Highlight? {
        article.allHighlights.first { $0.id == id }
    }

    private func createHighlight(_ intent: HighlightableTextView.HighlightIntent) -> UUID? {
        let h = Highlight(
            article: article,
            startOffset: intent.startOffset,
            endOffset: intent.endOffset,
            quotedText: intent.quotedText,
            color: intent.color
        )
        context.insert(h)
        try? context.save()
        Task { exportToObsidian(silent: true) }
        return h.id
    }

    /// Selection handles were dragged after the instant highlight was created:
    /// move the existing highlight instead of stacking a duplicate. Obsidian
    /// export is deferred to sheet dismiss / create / recolor / delete so
    /// handle drags don't thrash the filesystem.
    private func updateHighlight(id: UUID, range: NSRange, quotedText: String) {
        guard let h = findHighlight(id) else { return }
        h.startOffset = range.location
        h.endOffset = range.location + range.length
        h.quotedText = quotedText
        try? context.save()
    }

    private func recolorHighlight(id: UUID, color: HighlightColor) {
        guard let h = findHighlight(id) else { return }
        h.color = color
        lastHighlightColorRaw = color.rawValue
        try? context.save()
        Task { exportToObsidian(silent: true) }
    }

    private func deleteHighlight(id: UUID) {
        guard let h = findHighlight(id) else { return }
        context.delete(h)
        try? context.save()
        Task { exportToObsidian(silent: true) }
    }

    /// Runs when the edit sheet dismisses: perform a deferred delete, or
    /// persist whatever the sheet changed (note, color, range via handles).
    private func finishHighlightEditing() {
        focusNoteOnAppear = false
        if let id = pendingDeleteID {
            pendingDeleteID = nil
            deleteHighlight(id: id)
        } else {
            try? context.save()
            Task { exportToObsidian(silent: true) }
        }
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

extension View {
    /// Inline title + "minutes left" subtitle.
    func readerTitleBar(title: String, subtitle: String) -> some View {
        self
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension UIColor {
    var swiftUIColor: Color { Color(uiColor: self) }
}
