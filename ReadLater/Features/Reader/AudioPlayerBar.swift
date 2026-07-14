import SwiftUI
import SwiftData

/// Floating pink capsule shown while read-aloud is active. Left to right:
/// silk-ribbon waveform (doubles as a progress readout; tap to stop), speed
/// cycler, and a transport cluster (skip-back paragraph, pause/play,
/// skip-forward paragraph). While OpenAI is synthesizing the first chunk, the
/// waveform is replaced by a "Loading" label and the play control becomes a
/// cancel button with a spinner ring.
struct AudioPlayerBar: View {
    let controller: TTSController
    @Bindable var settings: AppSettings

    private static let speedSteps: [Double] = [1.0, 1.25, 1.5, 2.0, 0.75]

    var body: some View {
        HStack(spacing: 14) {
            Button {
                controller.stop()
            } label: {
                Group {
                    if controller.isBuffering {
                        loadingLabel
                    } else {
                        SilkWaveformView(isAnimating: controller.isPlaying, progress: controller.progress)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isBuffering ? "Cancel loading" : "Stop listening")

            Button {
                cycleSpeed()
            } label: {
                Text(Self.speedLabel(for: controller.rate))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(controller.isBuffering)
            .opacity(controller.isBuffering ? 0.45 : 1)
            .accessibilityLabel("Playback speed")

            transportCluster
                .disabled(controller.isBuffering)
                .opacity(controller.isBuffering ? 0.45 : 1)

            transportButton
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .playerGlassCapsule()
    }

    /// Previous / next paragraph. The engine is paragraph-based, so these skip
    /// whole paragraphs rather than a fixed number of seconds.
    private var transportCluster: some View {
        HStack(spacing: 18) {
            Button {
                controller.skipBackward()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.body.weight(.semibold))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous paragraph")

            Button {
                controller.skipForward()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body.weight(.semibold))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next paragraph")
        }
    }

    private var loadingLabel: some View {
        Text("Loading")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var transportButton: some View {
        Button {
            controller.togglePlayPause()
        } label: {
            ZStack {
                if controller.isBuffering {
                    BufferingCancelControl()
                } else {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            controller.isBuffering
                ? "Cancel loading"
                : (controller.isPlaying ? "Pause" : "Play")
        )
    }

    private func cycleSpeed() {
        let current = controller.rate
        let idx = Self.speedSteps.firstIndex(where: { abs($0 - current) < 0.01 }) ?? 0
        let next = Self.speedSteps[(idx + 1) % Self.speedSteps.count]
        settings.ttsRate = next
        controller.setRate(next)
    }

    static func speedLabel(for rate: Double) -> String {
        if abs(rate.rounded() - rate) < 0.01 {
            return "\(Int(rate.rounded()))x"
        }
        var s = String(format: "%.2f", rate)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + "x"
    }
}

/// Idle counterpart to `AudioPlayerBar`: the pink capsule shown when the reader
/// chrome is up but nothing is playing. Overflow · share · tag · play.
struct IdlePlayerBar: View {
    let article: Article
    var onTags: () -> Void
    var onPlay: () -> Void
    var onExport: () -> Void
    var onToggleRead: () -> Void
    var onReextract: () -> Void
    /// Disables the Re-extract menu item while a parse is in flight.
    var isReextracting: Bool

    var body: some View {
        HStack(spacing: 22) {
            Menu {
                Button {
                    onExport()
                } label: {
                    Label("Export to Obsidian", systemImage: "square.and.arrow.up")
                }
                Button {
                    onToggleRead()
                } label: {
                    Label(article.readAt == nil ? "Mark as Read" : "Mark as Unread",
                          systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
                }
                if let url = article.url {
                    Divider()
                    Button {
                        onReextract()
                    } label: {
                        Label("Re-extract", systemImage: "arrow.clockwise")
                    }
                    .disabled(isReextracting)
                    Link(destination: url) {
                        Label("Open Original", systemImage: "safari")
                    }
                }
            } label: {
                if isReextracting {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                } else {
                    capsuleGlyph("ellipsis")
                }
            }
            .accessibilityLabel(isReextracting ? "Re-extracting" : "More")

            if let url = article.url {
                ShareLink(item: url) {
                    capsuleGlyph("square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }

            Button(action: onTags) {
                capsuleGlyph("tag.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tags")

            Button(action: onPlay) {
                capsuleGlyph("play.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Listen")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
        .playerGlassCapsule()
    }

    private func capsuleGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .frame(width: 30, height: 30)
            .contentShape(.rect)
    }
}

/// Stop glyph inside a spinning indeterminate ring — used while OpenAI is
/// synthesizing the first paragraph. White to sit on the pink capsule.
private struct BufferingCancelControl: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate * 1.6
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(turns * 360))
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(width: 28, height: 28)
        }
        .accessibilityHidden(true)
    }
}

/// Continuous "silk ribbon" waveform: a soft filled body under a bright top
/// line plus a fainter trailing line, undulating via layered sine motion while
/// speaking and freezing to a static curve when paused. The already-spoken
/// fraction renders at full brightness; the upcoming fraction fades back, so
/// the ribbon doubles as an at-a-glance position readout. White on pink.
private struct SilkWaveformView: View {
    let isAnimating: Bool
    /// 0...1 fraction of the article already spoken.
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let clamped = CGFloat(min(max(progress, 0), 1))
                let playedX = size.width * clamped

                // Upcoming fraction — dimmed.
                if playedX < size.width {
                    var upcoming = context
                    upcoming.clip(to: Path(CGRect(x: playedX, y: 0,
                                                  width: size.width - playedX, height: size.height)))
                    drawRibbon(in: &upcoming, size: size, t: t, alpha: 0.4)
                }
                // Played fraction — full brightness.
                if playedX > 0 {
                    var played = context
                    played.clip(to: Path(CGRect(x: 0, y: 0, width: playedX, height: size.height)))
                    drawRibbon(in: &played, size: size, t: t, alpha: 1.0)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawRibbon(in context: inout GraphicsContext, size: CGSize, t: TimeInterval, alpha: Double) {
        let w = size.width
        let h = size.height
        let mid = Double(h) / 2

        // Envelope-modulated sine: the second sine slowly reshapes the first so
        // the ribbon never looks like a repeating pattern.
        func y(_ px: CGFloat, amp: Double, k: Double, sp: Double, offset: Double = 0) -> CGFloat {
            let x = Double(px)
            let v = mid + sin(x * k + t * sp) * amp * sin(x * 0.012 + t * 0.6) + offset
            return CGFloat(v)
        }

        let bodyAmp = Double(h) * 0.30
        let step: CGFloat = 2

        // Filled body between the top curve and its mirror about the centerline.
        var body = Path()
        body.move(to: CGPoint(x: 0, y: y(0, amp: bodyAmp, k: 0.055, sp: 3.1)))
        var px: CGFloat = 0
        while px <= w {
            body.addLine(to: CGPoint(x: px, y: y(px, amp: bodyAmp, k: 0.055, sp: 3.1)))
            px += step
        }
        px = w
        while px >= 0 {
            let top = y(px, amp: bodyAmp, k: 0.055, sp: 3.1)
            body.addLine(to: CGPoint(x: px, y: CGFloat(Double(h) - Double(top))))
            px -= step
        }
        body.closeSubpath()
        context.fill(body, with: .color(.white.opacity(0.22 * alpha)))

        // Bright top line.
        var top = Path()
        top.move(to: CGPoint(x: 0, y: y(0, amp: Double(h) * 0.32, k: 0.05, sp: 3.4)))
        px = 0
        while px <= w {
            top.addLine(to: CGPoint(x: px, y: y(px, amp: Double(h) * 0.32, k: 0.05, sp: 3.4)))
            px += 1
        }
        context.stroke(top, with: .color(.white.opacity(0.95 * alpha)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Fainter trailing line, phase-shifted the other way.
        var trail = Path()
        trail.move(to: CGPoint(x: 0, y: y(0, amp: Double(h) * 0.24, k: 0.07, sp: -2.2, offset: 2)))
        px = 0
        while px <= w {
            trail.addLine(to: CGPoint(x: px, y: y(px, amp: Double(h) * 0.24, k: 0.07, sp: -2.2, offset: 2)))
            px += 1
        }
        context.stroke(trail, with: .color(.white.opacity(0.45 * alpha)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}

extension Color {
    /// Figma `Accents/Pink` — the player capsule accent.
    static let playerPink = Color(red: 1.0, green: 45.0 / 255.0, blue: 85.0 / 255.0)
}

extension View {
    /// Prominent pink liquid-glass capsule for the audio / idle player.
    func playerGlassCapsule() -> some View {
        self.glassEffect(.regular.tint(.playerPink).interactive(), in: .capsule)
    }
}
