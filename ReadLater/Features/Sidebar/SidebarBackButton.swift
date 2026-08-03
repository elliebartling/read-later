import SwiftUI

/// The action that peels layer 1 (the group/list card) off layer 0 (the
/// sidebar). Published by `SidebarShell` and `nil` whenever peeling isn't
/// available — inside the reader, for instance, where back means *pop*.
private struct PeelToSidebarKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var peelToSidebar: (() -> Void)? {
        get { self[PeelToSidebarKey.self] }
        set { self[PeelToSidebarKey.self] = newValue }
    }
}

/// The leading-slot affordance on every layer-1 root: a back chevron that
/// peels the card away and reveals the sidebar.
///
/// It replaced the Settings gear (issue #57) — Settings is a sidebar row now —
/// and it is the *only* sidebar trigger: there is no floating button and no
/// global edge-swipe drawer, because that gesture belongs to back navigation.
///
/// Renders nothing when no peel action is in the environment, so a view that
/// adopts it can still be pushed somewhere else without growing a dead button.
struct SidebarBackButton: View {
    @Environment(\.peelToSidebar) private var peel

    var body: some View {
        if let peel {
            Button(action: peel) {
                // I2 — one weight, one scale, sized to the adjacent nav title.
                Image(systemName: "chevron.left")
                    .imageScale(.medium)
                    .fontWeight(.medium)
            }
            .accessibilityLabel("Back to sources")
        }
    }
}

extension View {
    /// Installs the back-to-sidebar affordance in the leading toolbar slot.
    /// Every layer-1 root (Library, All Items, a feed, Highlights, Search)
    /// calls this and nothing else does.
    func sidebarBackToolbarItem() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarBackButton()
            }
        }
    }
}
