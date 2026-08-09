import SwiftUI

/// Settings → Reddit Account. Signed-out: a single "Sign in with Reddit" button.
/// Signed-in: the connected account, entry points to the two imports (subreddits
/// and saved posts), and Sign Out. Hidden entirely when the feature isn't
/// configured (no client ID) — the caller (`SettingsView`) gates on
/// `RedditAuthController.isConfigured` before offering the row.
struct RedditAccountView: View {
    @State private var reddit = RedditAuthController.shared
    @State private var showingSignOutConfirm = false

    var body: some View {
        Form {
            if let account = reddit.account {
                signedInSections(account: account)
            } else {
                signedOutSection
            }

            if let error = reddit.lastError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Semantic.destructive)
                }
            }
        }
        .pageForm()
        .navigationTitle("Reddit")
        .navigationBarTitleDisplayMode(.inline)
        .phosphorBackButton()
        .confirmationDialog(
            "Sign out of Reddit?",
            isPresented: $showingSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await reddit.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your Reddit tokens from this device. Imported articles stay in your library.")
        }
    }

    @ViewBuilder
    private func signedInSections(account: RedditAccount) -> some View {
        Section {
            HStack {
                Image(.userCircle).uiGlyph(size: Font.GlyphSize.emptyStateMark)
                    .foregroundStyle(Semantic.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.subheadline.weight(.semibold))
                    Text("u/\(account.name)")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                }
            }
        }

        Section {
            NavigationLink {
                RedditSubredditPickerView()
            } label: {
                Label("Import Subreddits", icon: .listChecks)
            }
            NavigationLink {
                RedditSavedImportView()
            } label: {
                Label("Import Saved Posts", icon: .bookmark)
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Subscribe to your subreddits as feeds, or bring your Reddit saved posts into your library as articles you can highlight and export.")
        }

        Section {
            // **C1 / T7.** Was `Button("Sign Out", role: .destructive)`, which
            // is plain tinted text as a button (banned) in Title Case (banned).
            // `SiteLoginsView` already made this exact conversion for its own
            // sign-out row; this is the last copy of the pattern.
            FormRowButton(title: "Sign out", isDestructive: true) {
                showingSignOutConfirm = true
            }
        }
    }

    @ViewBuilder
    private var signedOutSection: some View {
        Section {
            Button {
                Task { await reddit.signIn() }
            } label: {
                HStack {
                    Image(.arrowCircleRight).uiGlyph(size: Font.GlyphSize.body)
                    Text("Sign in with Reddit")
                    Spacer()
                    if reddit.isAuthenticating {
                        ProgressView()
                    }
                }
                // The row states its own colour instead of inheriting whatever
                // the ambient tint resolves to — A3, so an accent rebind cannot
                // silently turn a settings row into a coloured one.
                .foregroundStyle(Ink.primary)
            }
            .buttonStyle(.plain)
            .disabled(reddit.isAuthenticating)
        } footer: {
            Text("Sign in to import your subreddits and saved posts, and to save posts back to Reddit from the reader. Read Later never sees your Reddit password — sign-in happens in a secure Reddit web page.")
        }
    }
}
