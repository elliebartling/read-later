import SwiftUI

/// Renders a `.divider` block as a short, theme-tinted hairline centered in the
/// reading column (~33% of the container width).
struct DividerBlockView: View {
    let theme: ReaderTheme

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color(uiColor: theme.foreground).opacity(0.15))
                .frame(width: geo.size.width * 0.33, height: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 1)
        .padding(.vertical, 16)
    }
}
