import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Insert this as the first row of a `List` (or the top of a `ScrollView`
/// content) so its Y position broadcasts via `ScrollOffsetPreferenceKey`.
struct ScrollDetectorRow: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .global).minY
                )
        }
        .frame(height: 0)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

extension View {
    /// Hides the tab bar when the user scrolls down and restores it when they
    /// scroll up. Requires `ScrollDetectorRow` to be present in the tracked
    /// scroll surface.
    func hidesTabBarOnScrollDown() -> some View {
        modifier(HidesTabBarOnScrollDown())
    }
}

private struct HidesTabBarOnScrollDown: ViewModifier {
    @State private var visibility: Visibility = .visible
    @State private var lastOffset: CGFloat = 0
    @State private var haveBaseline = false

    func body(content: Content) -> some View {
        content
            .toolbar(visibility, for: .tabBar)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { new in
                if !haveBaseline {
                    lastOffset = new
                    haveBaseline = true
                    return
                }
                let delta = new - lastOffset
                guard abs(delta) > 12 else { return }
                let next: Visibility = delta < 0 ? .hidden : .visible
                if next != visibility {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        visibility = next
                    }
                }
                lastOffset = new
            }
    }
}
