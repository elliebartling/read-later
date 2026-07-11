import SwiftUI
import SwiftData

/// Floating glass capsule shown while read-aloud is active. Left to right:
/// animated waveform (doubles as a progress readout; tap to stop), voice
/// selector, speed cycler, pause/play. Matches the reader mockup — no
/// scrubber; time remaining lives in the navigation subtitle.
struct AudioPlayerBar: View {
    let controller: TTSController
    @Bindable var settings: AppSettings

    private static let speedSteps: [Double] = [1.0, 1.25, 1.5, 2.0, 0.75]

    var body: some View {
        HStack(spacing: 0) {
            Button {
                controller.stop()
            } label: {
                WaveformView(isAnimating: controller.isPlaying, progress: controller.progress)
                    .frame(width: 88, height: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop listening")

            Spacer(minLength: 12)

            voiceMenu

            Spacer(minLength: 12)

            Button {
                cycleSpeed()
            } label: {
                Text(Self.speedLabel(for: controller.rate))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")

            Spacer(minLength: 12)

            Button {
                controller.togglePlayPause()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .playerGlassCapsule()
    }

    private var voiceMenu: some View {
        Menu {
            switch settings.ttsProvider {
            case .openAI:
                Picker("Voice", selection: openAIVoiceBinding) {
                    ForEach(VoiceCatalog.openAIVoices, id: \.self) { v in
                        Text(v.capitalized).tag(v)
                    }
                }
            case .apple:
                Picker("Voice", selection: appleVoiceBinding) {
                    Text("Default").tag("")
                    ForEach(VoiceCatalog.appleVoices(), id: \.identifier) { v in
                        Text("\(v.name) (\(v.language))").tag(v.identifier)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                Text(VoiceCatalog.displayName(provider: settings.ttsProvider, voice: controller.voice))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice")
    }

    private var openAIVoiceBinding: Binding<String> {
        Binding(
            get: { settings.openAIVoice },
            set: { newVoice in
                settings.openAIVoice = newVoice
                controller.setVoice(newVoice)
            }
        )
    }

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { settings.appleVoiceID },
            set: { newVoice in
                settings.appleVoiceID = newVoice
                controller.setVoice(newVoice)
            }
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

/// Bar-style waveform that pulses while speaking and freezes when paused.
/// Bars ahead of `progress` render dimmed, giving an at-a-glance position
/// readout without a scrubber.
private struct WaveformView: View {
    let isAnimating: Bool
    /// 0...1 fraction of the article already spoken.
    let progress: Double

    private static let barCount = 14
    // Fixed pseudo-random heights used when frozen and as per-bar variation
    // while animating, so the wave looks organic rather than uniform.
    private static let seeds: [Double] = (0..<barCount).map { i in
        0.35 + 0.65 * abs(sin(Double(i) * 1.7 + 0.9))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    let fraction = Double(i) / Double(Self.barCount - 1)
                    Capsule(style: .continuous)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: barScale(index: i, time: t), anchor: .center)
                        .opacity(fraction <= progress ? 1.0 : 0.35)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }

    private func barScale(index: Int, time: TimeInterval) -> CGFloat {
        let seed = Self.seeds[index]
        guard isAnimating else { return CGFloat(seed * 0.6) }
        // Two offset sine waves per bar → lively, non-repeating-looking pulse.
        let phase = Double(index) * 0.55
        let wave = 0.5 + 0.5 * sin(time * 5.2 + phase) * sin(time * 1.7 + phase * 1.3)
        return CGFloat(max(0.15, (0.3 + 0.7 * wave) * seed))
    }
}

extension View {
    /// Liquid-glass capsule on iOS 26, material capsule with a soft shadow on
    /// earlier OSes / SDKs.
    @ViewBuilder
    func playerGlassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        #else
        self
            .background(.regularMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        #endif
    }
}
