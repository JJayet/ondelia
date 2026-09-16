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

        addCommand(center.nextTrackCommand) { $0.skipToNextChapter() }
        addCommand(center.previousTrackCommand) { $0.skipToPreviousChapter() }

        addPositionCommand(center.changePlaybackPositionCommand) { $0.seek(to: $1) }

        applyRemoteSkipInterval()
    }

    /// The lock screen shows the interval in its button glyph, so it has to be re-published
    /// whenever the setting changes — `setupRemoteCommands` runs before `ThemeManager` has
    /// even finished loading its defaults.
    func applyRemoteSkipInterval() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: ThemeManager.shared.skipForwardInterval.seconds)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: ThemeManager.shared.skipBackInterval.seconds)]
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
        if let image = CoverImageCache.image(for: audiobook) {
            info[MPMediaItemPropertyArtwork] = Self.artwork(for: image)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Builds the artwork outside any actor.
    ///
    /// `MPMediaItemArtwork` keeps the request handler and calls it later on MediaPlayer's own
    /// queue. Declared inside a main-actor member the closure inherits that isolation, and the
    /// first call from MediaPlayer trips Swift's executor check and traps. Nothing here needs
    /// the main actor: it reads an image and hands it back.
    private nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Wipes the system's Now Playing entry, for when the book it described is gone.
    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
