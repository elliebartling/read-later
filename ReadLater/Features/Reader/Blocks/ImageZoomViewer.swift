import SwiftUI

/// Full-screen, pinch-to-zoom viewer for an inline article image.
///
/// Presented as a `fullScreenCover` from `ImageBlockView` when the reader taps
/// an image. It loads a near-full-resolution decode from `ArticleImageCache`
/// (the block reader only holds a downsampled thumbnail) and supports:
/// - pinch to zoom (`MagnifyGesture`), clamped to 1×…`maxScale`,
/// - double-tap to toggle between fit and a 2.5× zoom centred on the tap,
/// - drag to pan while zoomed, and drag-down to dismiss while at fit scale,
/// - a close button and a VoiceOver escape action.
///
/// The chrome always renders dark (a neutral photo-viewer surface) and keeps the
/// close button inside the safe area.
struct ImageZoomViewer: View {
    let src: URL
    let alt: String?

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var didFail = false

    /// Committed zoom scale; `gestureScale` layers the live pinch on top.
    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    /// Committed pan offset; `gesturePan` layers the live drag on top.
    @State private var offset: CGSize = .zero
    @GestureState private var gesturePan: CGSize = .zero

    /// Vertical travel of a drag-to-dismiss gesture (only active at fit scale).
    @State private var dismissDrag: CGFloat = 0

    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5
    private let dismissThreshold: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop
                content(in: proxy.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .statusBarHidden()
        .task(id: src) { await load() }
        .accessibilityAction(.escape) { dismiss() }
    }

    // MARK: - Layers

    /// Black surface that fades out as the dismiss drag progresses.
    private var backdrop: some View {
        Color.black
            .opacity(backdropOpacity)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let image {
            imageLayer(image, in: size)
        } else if didFail {
            failureLayer
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    private func imageLayer(_ image: UIImage, in size: CGSize) -> some View {
        let effectiveScale = scale * gestureScale
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(effectiveScale)
            .offset(combinedOffset)
            .gesture(magnify(in: size, image: image))
            .simultaneousGesture(drag(in: size, image: image))
            .onTapGesture(count: 2) { location in
                toggleZoom(around: location, in: size, image: image)
            }
            .accessibilityLabel(alt ?? "Image")
            .accessibilityAddTraits(.isImage)
            .animation(.interactiveSpring, value: scale)
            .animation(.interactiveSpring, value: offset)
    }

    private var failureLayer: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 44))
            Text("Couldn't load image")
                .font(.callout)
        }
        .foregroundStyle(.white.opacity(0.6))
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(11)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
        .accessibilityLabel("Close")
        .opacity(backdropOpacity)
    }

    // MARK: - Derived layout

    private var combinedOffset: CGSize {
        CGSize(
            width: offset.width + gesturePan.width,
            height: offset.height + gesturePan.height + dismissDrag
        )
    }

    /// Backdrop and chrome dim proportionally to how far a dismiss drag has
    /// travelled, bottoming out at 40% so the image stays visible mid-swipe.
    private var backdropOpacity: Double {
        let progress = min(abs(dismissDrag) / (dismissThreshold * 2), 1)
        return 1 - Double(progress) * 0.6
    }

    // MARK: - Gestures

    private func magnify(in size: CGSize, image: UIImage) -> some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let proposed = scale * value.magnification
                scale = min(max(proposed, 1), maxScale)
                if scale <= 1 {
                    offset = .zero
                } else {
                    offset = clampedOffset(offset, scale: scale, in: size, image: image)
                }
            }
    }

    private func drag(in size: CGSize, image: UIImage) -> some Gesture {
        DragGesture()
            .updating($gesturePan) { value, state, _ in
                guard scale > 1 else { return }
                state = value.translation
            }
            .onChanged { value in
                guard scale <= 1 else { return }
                // Only a predominantly-vertical drag arms dismissal.
                if abs(value.translation.height) > abs(value.translation.width) {
                    dismissDrag = value.translation.height
                }
            }
            .onEnded { value in
                if scale > 1 {
                    offset = clampedOffset(
                        CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        ),
                        scale: scale,
                        in: size,
                        image: image
                    )
                } else if abs(value.translation.height) > dismissThreshold {
                    dismiss()
                } else {
                    withAnimation(.spring) { dismissDrag = 0 }
                }
            }
    }

    private func toggleZoom(around location: CGPoint, in size: CGSize, image: UIImage) {
        withAnimation(.spring(duration: 0.3)) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = doubleTapScale
                // Recentre so the tapped point moves toward the middle.
                let dx = (size.width / 2 - location.x) * (doubleTapScale - 1)
                let dy = (size.height / 2 - location.y) * (doubleTapScale - 1)
                offset = clampedOffset(
                    CGSize(width: dx, height: dy),
                    scale: doubleTapScale,
                    in: size,
                    image: image
                )
            }
        }
    }

    /// Keeps `proposed` within the overflow the scaled image has beyond the
    /// container, so panning can't drag the picture off into empty space.
    private func clampedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        in size: CGSize,
        image: UIImage
    ) -> CGSize {
        let fitted = fittedSize(of: image, in: size)
        let maxX = max(0, (fitted.width * scale - size.width) / 2)
        let maxY = max(0, (fitted.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    /// The `scaledToFit` size of `image` inside `container` at 1× — the basis for
    /// pan-bound maths.
    private func fittedSize(of image: UIImage, in container: CGSize) -> CGSize {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0
        else { return container }
        let ratio = min(
            container.width / imageSize.width,
            container.height / imageSize.height
        )
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    // MARK: - Loading

    private func load() async {
        let loaded = await ArticleImageCache.shared.fullImage(for: src)
        if let loaded {
            image = loaded
        } else {
            didFail = true
        }
    }
}
