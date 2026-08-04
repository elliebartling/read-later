import SwiftUI

/// Settings → Site Logins. Lists the sites the user has a durable login for
/// (see `SiteLoginStore.signedInSites()` for the cookie-noise filtering that
/// makes this read as "sites" rather than raw cookie domains) and lets them
/// sign out of any one, purging that site's cookies and cached data on-device.
struct SiteLoginsView: View {
    @State private var model = SiteLoginsModel()

    var body: some View {
        Group {
            if model.isLoading, model.sites.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.loadFailed {
                // E2/E3 — one template, and a failure takes the warning hue.
                EmptyStateView(
                    mark: "exclamationmark.triangle",
                    title: "Can't load site logins",
                    message: "The browser data store didn't respond. Try again in a moment.",
                    isFailure: true,
                    actionTitle: "Retry",
                    action: { Task { await model.load() } }
                )
                .pageBackground()
            } else if model.sites.isEmpty {
                // The constitution names this state as the template every other
                // empty state copies: it explains the mechanism that would fill
                // the void rather than naming the void.
                EmptyStateView(
                    mark: "person.badge.key",
                    title: "No site logins",
                    message: "When you sign in to a member-only article from its reader banner, that site shows up here so you can manage it or sign out."
                )
                .pageBackground()
            } else {
                siteList
            }
        }
        .navigationTitle("Site logins")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .confirmationDialog(
            model.pendingSignOut.map { "Sign out of \($0)?" } ?? "",
            isPresented: Binding(
                get: { model.pendingSignOut != nil },
                set: { if !$0 { model.pendingSignOut = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingSignOut
        ) { host in
            Button("Sign out", role: .destructive) {
                Task { await model.confirmSignOut(host) }
            }
            Button("Cancel", role: .cancel) { model.pendingSignOut = nil }
        } message: { _ in
            Text("Saved articles keep their text; future fetches will be anonymous.")
        }
    }

    private var siteList: some View {
        List {
            Section {
                ForEach(model.sites, id: \.self) { host in
                    // I5 — no glyph in a list-row body; the host is the row.
                    HStack {
                        Text(host)
                        Spacer()
                        Button("Sign out") { model.pendingSignOut = host }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Semantic.destructive)
                            .accessibilityLabel("Sign out of \(host)")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Sign out", role: .destructive) {
                            model.pendingSignOut = host
                        }
                    }
                }
            } footer: {
                Text("Signing out clears the site's cookies and cached data on this device. Saved articles keep their text; future fetches will be anonymous.")
            }
        }
        .pageList()
        .refreshable { await model.load() }
    }
}

/// Backs `SiteLoginsView`: loads the filtered site list off the shared
/// `SiteLoginStore` and drives per-site sign-out, refreshing afterward.
@MainActor
@Observable
final class SiteLoginsModel {
    private(set) var sites: [String] = []
    private(set) var isLoading = true
    /// True when the last load threw (e.g. `SiteLoginStoreError.timedOut` —
    /// the store query is deadline-guarded and can fail instead of hanging).
    /// Drives the retryable error state; never leaves the user on a spinner.
    private(set) var loadFailed = false
    /// The site awaiting sign-out confirmation, or `nil` when no dialog is up.
    var pendingSignOut: String?

    private let store: SiteLoginStore

    init(store: SiteLoginStore = .shared) {
        self.store = store
    }

    func load() async {
        isLoading = true
        loadFailed = false
        do {
            sites = try await store.signedInSites()
        } catch {
            sites = []
            loadFailed = true
        }
        isLoading = false
    }

    func confirmSignOut(_ host: String) async {
        pendingSignOut = nil
        // A failed purge is not silently swallowed: the reload below re-reads
        // the jar, so any cookies that survived show right back up in the list.
        try? await store.signOut(host: host)
        await load()
    }
}
