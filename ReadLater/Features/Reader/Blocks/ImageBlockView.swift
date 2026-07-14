import SwiftUI

/// Renders a single `.image` article block. Reserves an aspect-ratio box from
/// the block's intrinsic `width`/`height` (so nothing jumps when the image
/// arrives), loads a downsampled bitmap through `ArticleImageCache`, and fades
/// it in. A failed or missing load collapses to a compact placeholder.
///
/// Captions are not rendered here — they are their own `.caption` blocks.
struct ImageBlockView: View {
    let block: ArticleBlock
    let containerWidth: CGFloat
    let theme: ReaderTheme

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var isZoomed = false

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(block.alt ?? "Image")
            .accessibilityAddTraits(canZoom ? [.isImage, .isButton] : .isImage)
            .accessibilityHint(canZoom ? "Opens full screen" : "")
            .accessibilityAction { if canZoom { isZoomed = true } }
            .task(id: block.src) { await load() }
            .fullScreenCover(isPresented: $isZoomed) {
                if let src = block.src {
                    ImageZoomViewer(src: src, alt: block.alt)
                }
            }
    }

    /// A tap opens the viewer only once a real bitmap has loaded.
    private var canZoom: Bool { image != nil && block.src != nil }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: reservedHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture { if canZoom { isZoomed = true } }
        } else if didFail {
            failurePlaceholder
        } else {
            loadingPlaceholder
        }
    }

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(placeholderFill)
            .frame(maxWidth: .infinity)
            .frame(height: reservedHeight)
    }

    private var failurePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(placeholderFill)
            .frame(maxWidth: .infinity, minHeight: 40)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(uiColor: theme.foreground).opacity(0.3))
            )
    }

    private var placeholderFill: Color {
        Color(uiColor: theme.foreground).opacity(0.06)
    }

    /// Height of the reserved box: the intrinsic aspect ratio when both
    /// dimensions are known (capped at 1.4× width for panoramas, floored at
    /// 44 pt), otherwise a 4:3 default.
    private var reservedHeight: CGFloat {
        let width = max(containerWidth, 1)
        if let w = block.width, let h = block.height, w > 0, h > 0 {
            let aspectHeight = width * CGFloat(h) / CGFloat(w)
            return max(44, min(aspectHeight, width * 1.4))
        }
        return width * 3.0 / 4.0
    }

    private func load() async {
        guard let src = block.src else {
            didFail = true
            return
        }
        let width = max(containerWidth, 1)
        let loaded = await ArticleImageCache.shared.image(for: src, targetWidth: width)
        if let loaded {
            withAnimation(.easeIn(duration: 0.25)) { image = loaded }
        } else {
            didFail = true
        }
    }
}
