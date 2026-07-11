import Foundation
import MediaPlayer

/// Mirrors TTS playback onto the lock screen / Control Center and handles
/// remote commands (headphone buttons, lock-screen controls). Owned by
/// TTSController; safe to activate/deactivate repeatedly.
@MainActor
final class NowPlayingManager {

    private weak var controller: TTSController?
    /// (command, target) pairs installed on the shared command center, kept so
    /// deactivate() can remove exactly what this instance added.
    private var installedTargets: [(MPRemoteCommand, Any)] = []

    func activate(controller: TTSController) {
        self.controller = controller
        installCommandsIfNeeded()
    }

    func update(title: String, artist: String?, elapsed: TimeInterval, duration: TimeInterval, playbackRate: Double) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
        ]
        if let artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func deactivate() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        for (command, target) in installedTargets {
            command.removeTarget(target)
        }
        installedTargets.removeAll()
    }

    private func installCommandsIfNeeded() {
        guard installedTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        func install(_ command: MPRemoteCommand, handler: @escaping (TTSController) -> MPRemoteCommandHandlerStatus) {
            let target = command.addTarget { [weak self] _ in
                guard let controller = self?.controller else { return .commandFailed }
                return handler(controller)
            }
            installedTargets.append((command, target))
        }

        install(center.playCommand) { controller in
            guard controller.state == .paused else { return .commandFailed }
            controller.resume()
            return .success
        }
        install(center.pauseCommand) { controller in
            guard controller.state == .playing else { return .commandFailed }
            controller.pause()
            return .success
        }
        install(center.togglePlayPauseCommand) { controller in
            guard controller.isActive else { return .commandFailed }
            controller.togglePlayPause()
            return .success
        }
        install(center.nextTrackCommand) { controller in
            guard controller.isActive else { return .commandFailed }
            controller.skipForward()
            return .success
        }
        install(center.previousTrackCommand) { controller in
            guard controller.isActive else { return .commandFailed }
            controller.skipBackward()
            return .success
        }
    }
}
