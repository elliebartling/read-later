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
    /// True while a Re-extract parse is running — disables the menu item.
    @State private var isReextracting = false
    /// Drives the in-app site-login sheet, opened from the member-only banner.
    /// Dismissing it re-extracts so a now-authenticated session resolves the
    /// preview to the full article.
    @State private var showingSiteLogin = false
    /// Non-nil drives the "Couldn't re-extract" alert (parallels `tts.lastError`).
    @State private var reextractError: String?
    /// Non-nil drives the transient success toast after a re-extract finishes,
    /// so a parse that produces identical text still gives visible feedback
    /// instead of looking like the button did nothing.
    @State private var reextractToast: String?
    /// Caches the decoded `[ArticleBlock]` so `article.blocks` (which JSON-decodes
    /// on every access) runs once per blocks change, not once per body pass.
    @State private var blocksCache = DecodedBlocksCache()
    /// UTF-16 index of the character at the top of the viewport, updated while
    /// reading and written back to the article on disappear so reopening resumes
    /// at the same word instead of jumping to the top.
    @State private var latestTopOffset: Int?
    /// Non-nil presents the in-app browser for a discussion permalink (the
    /// "In-App Browser" option of the Open-discussions-in setting).
    @State private var inAppDiscussion: IdentifiableURL?

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

            floatingPlayer
        }
        .overlay(alignment: .top) { topStatusOverlay }
        .animation(Self.chromeAnimation, value: isReextracting)
        .animation(Self.chromeAnimation, value: reextractToast)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: tts.isActive)
        .readerTitleBar(title: article.title, subtitle: subtitleText)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
        .statusBarHidden(!showChrome)
        .toolbar(.hidden, for: .bottomBar)
        .toolbar {
            if article.isVideoArticle {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: watchOnYouTube) {
                        Image(systemName: "play.rectangle.fill")
                    }
                    .accessibilityLabel("Watch on YouTube")
                }
            }
            if article.discussionURL != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openDiscussion) {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    .accessibilityLabel("View discussion")
                    .contextMenu {
                        Button {
                            if let url = article.discussionURL {
                                DiscussionOpener.openInBrowser(url)
                            }
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                    }
                }
            }
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
        .sheet(item: $inAppDiscussion) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingSiteLogin, onDismiss: reextract) {
            if let url = article.url {
                SiteLoginView(url: url)
            }
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
        .alert(
            "Couldn't re-extract",
            isPresented: Binding(
                get: { reextractError != nil },
                set: { if !$0 { reextractError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reextractError ?? "")
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
                    onToggleRead: toggleRead,
                    onReextract: reextract,
                    isReextracting: isReextracting
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    /// Floating status region pinned below the top chrome. Priority order:
    /// an in-progress re-extract spinner, then the transient completion toast,
    /// then the persistent "member-only preview" notice (shown alongside chrome
    /// so it never intrudes on immersive reading). Exactly one shows at a time.
    @ViewBuilder
    private var topStatusOverlay: some View {
        Group {
            if isReextracting {
                statusPill(systemImage: nil) {
                    ProgressView().controlSize(.small)
                    Text("Re-extracting…")
                }
            } else if let toast = reextractToast {
                statusPill(systemImage: "checkmark.circle.fill") {
                    Text(toast)
                }
            } else if article.isPaywalledPartial, showChrome {
                paywallBanner
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Member-only notice. When we know the article's host, the whole pill is a
    /// button that opens the in-app site-login sheet ("Sign in to <host>"); once
    /// the user signs in and the sheet dismisses, the reader re-extracts and,
    /// if the full article comes back, `isPaywalledPartial` clears and this
    /// banner disappears on its own. Falls back to the passive notice when there
    /// is no URL to sign into.
    @ViewBuilder
    private var paywallBanner: some View {
        if let host = signInHost {
            Button {
                showingSiteLogin = true
            } label: {
                statusPill(systemImage: "lock.fill") {
                    Text("Member-only — Sign in to \(host)")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(host) so you can sign in and load the full story")
        } else {
            statusPill(systemImage: "lock.fill") {
                Text("Preview only — this story is member-only")
            }
        }
    }

    /// Host to offer sign-in for, trimmed of a `www.` prefix. Nil when the
    /// article has no URL (nothing to sign into).
    private var signInHost: String? {
        guard let host = article.url?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Neutral glass capsule used by `topStatusOverlay`. Distinct from the
    /// pink player capsule so status never reads as a transport control.
    private func statusPill(
        systemImage: String?,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            content()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    @ViewBuilder
    private var readerContent: some View {
        switch article.parseStatus {
        case .pending:
            parsingState
        case .failed:
            failedState
        case .ready:
            if let blocks = blocksCache.blocks(for: article), !blocks.isEmpty, settings.useBlockReader {
                BlockReaderView(
                    blocks: blocks,
                    plainText: article.plainText,
                    highlights: article.allHighlights,
                    currentParagraph: tts.currentParagraph,
                    isSpeaking: tts.isActive,
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
                    onTap: {
                        withAnimation(Self.chromeAnimation) { chromeVisible.toggle() }
                    }
                )
            } else {
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
                // Keep the text view full-screen under both bars so its frame
                // never moves when the chrome appears. ReaderTextView then pins
                // the text with a frozen inset, so revealing the nav bar has no
                // effect on where the article sits — the bar just overlays it.
                .ignoresSafeArea(.container, edges: .vertical)
            }
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
            // Re-extract routes through ArticleParsing.parse, so a video URL
            // re-routes to VideoArticleParser (and its metadata fallback) rather
            // than re-running the article extractor that "couldn't parse" it.
            Button {
                reextract()
            } label: {
                Text("Try Again")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReextracting)
            if let url = article.url {
                Link(destination: url) { Text("Open in Safari") }
                    .buttonStyle(.bordered)
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

    /// Opens the video on YouTube via the short `youtu.be/<id>` universal link —
    /// the YouTube app intercepts it when installed, else it opens in Safari.
    /// The lead affordance for video articles (transcript reading and TTS stay
    /// available but are not promoted — see the YouTube save design, decision 2).
    private func watchOnYouTube() {
        guard let id = YouTubeURL.videoID(from: article.url),
              let url = YouTubeURL.shareURL(videoID: id) ?? article.url
        else { return }
        UIApplication.shared.open(url)
    }

    /// Opens the article's discussion permalink honouring the user's
    /// "Open discussions in" preference. External hand-offs (System Default /
    /// Narwhal) go straight out; the in-app option presents a Safari sheet.
    private func openDiscussion() {
        guard let url = article.discussionURL else { return }
        if let inApp = DiscussionOpener.open(permalink: url, preference: settings.redditDiscussionApp) {
            inAppDiscussion = IdentifiableURL(url: inApp)
        }
    }

    /// Re-runs the extractor over the article's URL and refreshes its derived
    /// fields (plainText, extractedHTML, blocks, reading time) via the shared
    /// `Article.apply` helper — the same parse path used on first ingest. The
    /// user-visible title and existing highlights are left untouched; highlights
    /// re-anchor lazily on the next render. Failures surface in an alert.
    private func reextract() {
        guard let url = article.url, !isReextracting else { return }
        isReextracting = true
        reextractToast = nil
        // Keep the chrome up so the in-progress spinner (and, on finish, the
        // toast) is visible and the user retains a back button — a parse can
        // run for tens of seconds.
        withAnimation(Self.chromeAnimation) { chromeVisible = true }
        // Stop read-aloud before swapping the text out from under it — audio
        // reading stale paragraphs against refreshed text is a desync. No-op
        // when idle.
        tts.stop()
        Task { @MainActor in
            defer { isReextracting = false }
            do {
                let parsed = try await ArticleParsing.parse(url: url)
                article.apply(parsed, updateTitle: false)
                // Harmless when already ready; recovers an article stuck in
                // .failed whose re-extract succeeded.
                article.parseStatus = .ready
                try context.save()
                // Always confirm completion — even when the refreshed text is
                // byte-identical (e.g. a member-only preview re-served) — so the
                // action never looks like a silent no-op.
                showReextractToast(article.isPaywalledPartial
                    ? "Re-extracted — preview only (member-only source)"
                    : "Article re-extracted")
            } catch {
                reextractError = error.localizedDescription
            }
        }
    }

    /// Shows the completion toast and auto-dismisses it after a short beat.
    private func showReextractToast(_ message: String) {
        reextractToast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            // Only clear if this toast is still the one showing.
            if reextractToast == message {
                withAnimation(Self.chromeAnimation) { reextractToast = nil }
            }
        }
    }

    // MARK: - Highlight actions

    private func findHighlight(_ id: UUID) -> Highlight? {
        article.allHighlights.first { $0.id == id }
    }

    /// Snapshots the article's highlights for the pure merge planner,
    /// optionally excluding one (the session highlight being updated).
    private func mergeSnapshots(excluding excludedID: UUID? = nil) -> [HighlightMerge.Existing] {
        article.allHighlights
            .filter { $0.id != excludedID }
            .map {
                HighlightMerge.Existing(
                    id: $0.id,
                    startOffset: $0.startOffset,
                    endOffset: $0.endOffset,
                    note: $0.note,
                    createdAt: $0.createdAt
                )
            }
    }

    /// Re-derives the anchoring context for `h` after its range changed.
    private func refreshAnchorContext(_ h: Highlight) {
        let (prefix, suffix) = HighlightAnchor.contextAround(
            range: NSRange(location: h.startOffset, length: h.endOffset - h.startOffset),
            in: article.plainText
        )
        h.prefixContext = prefix
        h.suffixContext = suffix
    }

    /// Deletes the absorbed highlights named by `plan`, sparing `survivorID`.
    /// SwiftData deletes propagate through the CloudKit-synced store.
    private func deleteAbsorbed(_ plan: HighlightMerge.Plan, survivorID: UUID) {
        for id in plan.absorbed where id != survivorID {
            if let victim = findHighlight(id) {
                context.delete(victim)
            }
        }
    }

    /// Creates a highlight from a fresh selection — or, when the selection
    /// overlaps (or sits flush against) existing highlights, merges them all
    /// into one highlight spanning the union instead of stacking duplicates.
    /// The earliest-created overlapped highlight survives (keeping its
    /// `createdAt`, color, and Obsidian identity); the others are absorbed,
    /// with their notes folded into the survivor so nothing is lost. Returns
    /// the surviving highlight's ID so the selection session keeps updating it.
    private func createHighlight(_ intent: HighlightableTextView.HighlightIntent) -> UUID? {
        let plan = HighlightMerge.plan(
            newStart: intent.startOffset,
            newEnd: intent.endOffset,
            existing: mergeSnapshots(),
            plainText: article.plainText
        )

        if plan.didMerge,
           let survivorID = plan.absorbed.min(by: { lhs, rhs in
               let l = findHighlight(lhs)?.createdAt ?? .distantFuture
               let r = findHighlight(rhs)?.createdAt ?? .distantFuture
               return l < r
           }),
           let survivor = findHighlight(survivorID) {
            survivor.startOffset = plan.unionStart
            survivor.endOffset = plan.unionEnd
            survivor.quotedText = plan.quotedText
            survivor.note = plan.absorbedNote // all absorbed notes, incl. survivor's
            refreshAnchorContext(survivor)
            deleteAbsorbed(plan, survivorID: survivorID)
            try? context.save()
            Task { exportToObsidian(silent: true) }
            return survivor.id
        }

        let h = Highlight(
            article: article,
            startOffset: intent.startOffset,
            endOffset: intent.endOffset,
            quotedText: intent.quotedText,
            color: intent.color
        )
        refreshAnchorContext(h)
        context.insert(h)
        try? context.save()
        Task { exportToObsidian(silent: true) }
        return h.id
    }

    /// Selection handles were dragged after the instant highlight was created:
    /// move the existing highlight instead of stacking a duplicate. If the
    /// settled drag now overlaps (or touches) other highlights, they are
    /// absorbed into this one — union range, notes folded in, earliest
    /// `createdAt` kept. This runs only when the selection settles
    /// (editMenuForTextIn), never per pixel of drag, so merges don't churn.
    /// Obsidian export is deferred to sheet dismiss / create / recolor /
    /// delete so handle drags don't thrash the filesystem.
    private func updateHighlight(id: UUID, range: NSRange, quotedText: String) {
        guard let h = findHighlight(id) else { return }
        let plan = HighlightMerge.plan(
            newStart: range.location,
            newEnd: range.location + range.length,
            existing: mergeSnapshots(excluding: id),
            plainText: article.plainText
        )
        if plan.didMerge {
            h.startOffset = plan.unionStart
            h.endOffset = plan.unionEnd
            h.quotedText = plan.quotedText
            h.note = HighlightMerge.combineNotes(h.note, plan.absorbedNote)
            if let earliest = plan.earliestCreatedAt, earliest < h.createdAt {
                h.createdAt = earliest
            }
            refreshAnchorContext(h)
            deleteAbsorbed(plan, survivorID: id)
        } else {
            h.startOffset = range.location
            h.endOffset = range.location + range.length
            h.quotedText = quotedText
        }
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

/// Identifiable wrapper so a bare `URL` can drive `.sheet(item:)`.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
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

/// Caches the decoded `[ArticleBlock]` for the reader so the JSON blob is decoded
/// once per change rather than on every `article.blocks` access (which decodes
/// eagerly). Keyed on the raw `blocksJSON` bytes: a cheap `Data` compare catches
/// re-extract (which rewrites the blob without bumping `blocksVersion`).
final class DecodedBlocksCache {
    private var lastJSON: Data?
    private var decoded: [ArticleBlock]?

    func blocks(for article: Article) -> [ArticleBlock]? {
        let json = article.blocksJSON
        if json != lastJSON {
            lastJSON = json
            decoded = json.flatMap { ArticleBlocks.decode($0) }
        }
        return decoded
    }
}
