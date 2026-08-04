import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// One-time YouTube subscription import. Two sources, presented together:
/// a logged-in `feed/channels` DOM harvest (primary) and a Google Takeout
/// `subscriptions.csv` (robust fallback). Both land in the same checkbox picker;
/// selected channels are subscribed as RSS feeds via the wave-1 machinery.
///
/// Presented as a sheet from `FeedsView`. The harvest path opens `SiteLoginView`
/// on YouTube first so the user's Google session lands in the shared cookie jar;
/// the harvest then runs on dismiss. Failure states are honest and always point
/// at the CSV path — never an endless spinner (mirrors `SiteLoginsView`).
struct YouTubeImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var feeds: [Feed]

    @State private var model = YouTubeImportModel()
    @State private var showingLogin = false
    @State private var showingFileImporter = false

    private var existingChannelIDs: Set<String> {
        YouTubeImportModel.existingChannelIDs(in: feeds)
    }

    var body: some View {
        NavigationStack {
            content
                // T7 — sentence case.
                .navigationTitle("Import subscriptions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // §8.2 — an **Informational** sheet: nothing to commit, so
                    // `Done` trailing. It said "Close" in the leading slot,
                    // which was a fourth dismissal verb in a four-verb app.
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .sheet(isPresented: $showingLogin, onDismiss: {
                    Task { await model.runHarvest(existingChannelIDs: existingChannelIDs) }
                }) {
                    if let url = URL(string: "https://www.youtube.com/feed/channels") {
                        SiteLoginView(url: url)
                    }
                }
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.commaSeparatedText, .plainText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            model.importCSV(from: url, existingChannelIDs: existingChannelIDs)
                        }
                    case .failure:
                        break // user cancelled or picker failed; stay on source screen
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .chooseSource:
            sourceChooser
        case .harvesting:
            ProgressView("Reading your subscriptions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .picking:
            picker
        case .subscribing:
            subscribingMoment
        case .done(let added):
            doneView(added: added)
        case .failure(let message):
            failureView(message)
        }
    }

    /// **§9, playful moment 4** — "a live count ticking up as sources land.
    /// Numbers moving is the whole effect."
    ///
    /// This is one of the four moments the playfulness budget is spent on, and
    /// it is spent here rather than on a spinner labelled "Subscribing…" that
    /// tells the reader nothing while a 200-channel import runs for a minute.
    /// The number is the only thing that moves: no confetti, no bounce, no
    /// badge (§9's NOT list). The §10 **Attention** spring is the one curve
    /// with overshoot and this is one of the four places it is legal — and it
    /// still degrades to a crossfade under Reduce Motion (M3), because
    /// `motionAttention` resolves through `Motion.resolve`.
    private var subscribingMoment: some View {
        VStack(spacing: 10) {
            Text("\(model.subscribedCount)")
                .displayType()
                .monospacedDigit()
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
                .motionAttention(value: model.subscribedCount)
            Text(model.totalToSubscribe > 0
                ? "of \(model.totalToSubscribe) channels added"
                : "channels added")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.subscribedCount) of \(model.totalToSubscribe) channels added")
    }

    // MARK: - Source chooser

    private var sourceChooser: some View {
        List {
            Section {
                Button {
                    showingLogin = true
                } label: {
                    // I5 — no glyph in a list-row body, and SH4: a Button's
                    // explanatory subtitle is never tinted.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from YouTube").font(.body.weight(.semibold))
                            .foregroundStyle(Ink.primary)
                        Text("Sign in and we'll read your subscribed channels.")
                            .font(.footnote).foregroundStyle(Ink.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section {
                Button {
                    showingFileImporter = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Google Takeout").font(.body.weight(.semibold))
                            .foregroundStyle(Ink.primary)
                        Text("Pick the subscriptions.csv from your Takeout export.")
                            .font(.footnote).foregroundStyle(Ink.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("A one-time import — no ongoing sync. Channels become normal feeds you can unsubscribe any time.")
            }
        }
        .pageList()
    }

    // MARK: - Picker

    private var picker: some View {
        Group {
            if model.newChannels.isEmpty {
                EmptyStateView(
                    mark: .done,
                    title: "Nothing new to import",
                    message: model.alreadySubscribedCount > 0
                        ? "All \(model.alreadySubscribedCount) channels we found are already in your feeds."
                        : "No channels were found to import."
                )
                .pageBackground()
            } else {
                List {
                    Section {
                        ForEach(model.newChannels) { channel in
                            Button {
                                model.toggle(channel)
                            } label: {
                                HStack {
                                    Image(systemName: model.isSelected(channel) ? "checkmark.circle.fill" : "circle")
                                        .uiGlyph(size: Font.GlyphSize.body)
                                        .foregroundStyle(model.isSelected(channel) ? Accent.primary : Ink.secondary)
                                    Text(channel.title).foregroundStyle(Ink.primary)
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("^[\(model.newChannels.count) channel](inflect: true)")
                    } footer: {
                        if model.alreadySubscribedCount > 0 {
                            Text("\(model.alreadySubscribedCount) already in your feeds.")
                        }
                    }
                }
                // S1 — the one list style. This list was the last `List` in the
                // app still on the system default.
                .pageList()
            }
        }
        .toolbar {
            if !model.newChannels.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.allSelected ? "Deselect all" : "Select all") {
                        if model.allSelected { model.deselectAll() } else { model.selectAll() }
                    }
                }
            }
        }
        // §8.3 — the screen's ONE prominent capsule, in place of
        // `.buttonStyle(.borderedProminent)` (a fourth button vocabulary, and
        // the only place in the app the system tint still showed through).
        // SH3 — verb + object.
        .safeAreaInset(edge: .bottom) {
            if !model.newChannels.isEmpty {
                ProminentCapsuleButton(
                    title: model.selection.isEmpty
                        ? "Add feeds"
                        : "Add ^[\(model.selection.count) feed](inflect: true)",
                    fillsWidth: true
                ) {
                    Task { await model.subscribeSelected(context: context) }
                }
                .disabled(!model.canSubscribe)
                .opacity(model.canSubscribe ? 1 : 0.45)
                .padding(.horizontal, Metric.screenMargin)
                .padding(.bottom, Metric.containerGap)
            }
        }
    }

    // MARK: - Terminal states

    private func doneView(added: Int) -> some View {
        EmptyStateView(
            mark: .done,
            title: "Import complete",
            message: doneMessage(added: added),
            actionTitle: "Done",
            action: { dismiss() }
        )
        .pageBackground()
    }

    /// One sentence, per E2 — the skipped-channel note joins it rather than
    /// becoming a second paragraph.
    private func doneMessage(added: Int) -> String {
        var sentence = added > 0
            ? "Subscribed to ^[\(added) channel](inflect: true)."
            : "No new channels were subscribed."
        if model.failedCount > 0 {
            sentence += " \(model.failedCount) couldn't be reached and were skipped."
        }
        return sentence
    }

    private func failureView(_ message: String) -> some View {
        EmptyStateView(
            mark: .warning,
            title: "Import didn't work",
            message: message,
            isFailure: true,
            actionTitle: "Try Google Takeout",
            action: { showingFileImporter = true },
            secondaryActionTitle: "Back",
            secondaryAction: { model.reset() }
        )
        .pageBackground()
    }
}
