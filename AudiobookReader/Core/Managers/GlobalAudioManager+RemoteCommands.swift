import Foundation
import MediaPlayer
import UIKit

extension GlobalAudioManager {
    /// Registers the lock screen and Control Center transport controls.
    ///
    /// `MPRemoteCommandCenter` is a singleton, so these targets are registered once for the app.
    /// Both old engines added their own on every `init` and only removed them in `deinit`, so
    /// switching books left stale targets pointing at dead engines.
    func setupRemoteCommands() {
        guard remoteCommandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        addCommand(center.playCommand) { $0.resumePlayback() }
        addCommand(center.pauseCommand) { $0.pausePlayback() }
        addCommand(center.togglePlayPauseCommand) { $0.togglePlayback() }

        addSkipCommand(center.skipForwardCommand) { $0.skipForward($1) }
        addSkipCommand(center.skipBackwardCommand) { $0.skipBackward($1) }

        addPositionCommand(center.changePlaybackPositionCommand) { $0.seek(to: $1) }

        let interval = NSNumber(value: ThemeManager.shared.skipInterval.seconds)
        center.skipForwardCommand.preferredIntervals = [interval]
        center.skipBackwardCommand.preferredIntervals = [interval]
    }

    // MARK: - Registration
    //
    // Remote command handlers are delivered on an arbitrary queue — MediaPlayer promises
    // nothing about the thread — so each one hops to the main actor rather than asserting it
    // is already there. Anything the handler needs off the event is read before the hop,
    // because `MPRemoteCommandEvent` is not Sendable.

    private func addCommand(
        _ command: MPRemoteCommand,
        _ handler: @escaping @MainActor (GlobalAudioManager) -> Void
    ) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                handler(self)
            }
            return .success
        }
        remoteCommandTargets.append((command, target))
    }

    private func addSkipCommand(
        _ command: MPSkipIntervalCommand,
        _ handler: @escaping @MainActor (GlobalAudioManager, TimeInterval) -> Void
    ) {
        let target = command.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in
                guard let self else { return }
                handler(self, interval)
            }
            return .success
        }
        remoteCommandTargets.append((command, target))
    }

    private func addPositionCommand(
        _ command: MPChangePlaybackPositionCommand,
        _ handler: @escaping @MainActor (GlobalAudioManager, TimeInterval) -> Void
    ) {
        let target = command.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in
                guard let self else { return }
                handler(self, position)
            }
            return .success
        }
        remoteCommandTargets.append((command, target))
    }

    // MARK: - Now Playing

    /// Publishes the book itself. Called once per load, so the artwork is not rebuilt on
    /// every position update.
    func setupNowPlayingInfo(for audiobook: AudiobookModel) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: audiobook.title ?? "",
            MPMediaItemPropertyArtist: audiobook.author ?? "",
            MPMediaItemPropertyPlaybackDuration: getDuration(),
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        if let data = audiobook.coverImageData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Publishes position and rate. Cheap enough to call on every state change.
    func updateNowPlayingInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = getCurrentTime()
        info[MPMediaItemPropertyPlaybackDuration] = getDuration()
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackState == .playing ? getPlaybackRate() : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
