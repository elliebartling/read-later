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
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Reddit")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of Reddit?",
            isPresented: $showingSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
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
                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.subheadline.weight(.semibold))
                    Text("u/\(account.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            NavigationLink {
                RedditSubredditPickerView()
            } label: {
                Label("Import Subreddits", systemImage: "checklist")
            }
            NavigationLink {
                RedditSavedImportView()
            } label: {
                Label("Import Saved Posts", systemImage: "bookmark")
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Subscribe to your subreddits as feeds, or bring your Reddit saved posts into your library as articles you can highlight and export.")
        }

        Section {
            Button("Sign Out", role: .destructive) {
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
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Sign in with Reddit")
                    Spacer()
                    if reddit.isAuthenticating {
                        ProgressView()
                    }
                }
            }
            .disabled(reddit.isAuthenticating)
        } footer: {
            Text("Sign in to import your subreddits and saved posts, and to save posts back to Reddit from the reader. Read Later never sees your Reddit password — sign-in happens in a secure Reddit web page.")
        }
    }
}
