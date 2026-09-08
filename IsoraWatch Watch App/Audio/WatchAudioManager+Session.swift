import AVFoundation
import Foundation
import MediaPlayer

/// Audio session, the system Now Playing screen and the shared store the complication reads.
extension WatchAudioManager {
    /// watchOS only plays long-form audio to a Bluetooth route, and `activate()` is what puts
    /// the route picker on screen. A throw here means the listener has no headphones connected.
    ///
    /// Asked for on every play, not once: the route goes away with the headphones and the session
    /// with it, so a cached "already activated" would leave the watch playing to nothing.
    func activateAudioSession() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try await session.activate()
            setNeedsHeadphones(false)
            installRemoteCommands()
            return true
        } catch {
            Log.audio.error("❌ WatchAudioManager: audio session refused: \(error.localizedDescription)")
            setNeedsHeadphones(true)
            return false
        }
    }

    // MARK: - Now Playing

    func updateNowPlaying() {
        guard let book = currentBook else {
            NowPlayingSharedStore.write(
                audiobook: nil,
                isPlaying: false,
                currentTime: 0,
                duration: 0,
                coverImageData: nil
            )
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let chapter = currentChapter
        NowPlayingSharedStore.write(
            audiobook: book,
            isPlaying: player.isPlaying,
            currentTime: player.currentTime,
            duration: player.duration,
            coverImageData: book.coverImageData,
            playbackRate: player.playbackRate,
            chapter: chapter.map {
                (title: $0.title, number: Int($0.chapterNumber), start: $0.startTime, end: $0.endTime)
            }
        )
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: book.title ?? AudiobookModel.unknownTitle,
            MPMediaItemPropertyArtist: book.author ?? AudiobookModel.unknownAuthor,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? Double(player.playbackRate) : 0
        ]
    }

    // MARK: - Remote commands

    /// Registered once, the first time the session comes up: the targets outlive every book.
    private func installRemoteCommands() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        applyRemoteSkipIntervals()

        center.playCommand.addTarget { _ in Self.perform { $0.play() } }
        center.pauseCommand.addTarget { _ in Self.perform { $0.pause() } }
        center.togglePlayPauseCommand.addTarget { _ in Self.perform { $0.toggle() } }
        center.skipForwardCommand.addTarget { _ in Self.perform { $0.skipForward() } }
        center.skipBackwardCommand.addTarget { _ in Self.perform { $0.skipBackward() } }
    }

    /// Called on install and whenever a snapshot changes the phone's setting.
    func applyRemoteSkipIntervals() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: PhoneSyncService.shared.skipForwardSeconds)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: PhoneSyncService.shared.skipBackSeconds)]
    }

    /// The command targets are called on an arbitrary queue, so they only ever schedule work.
    private static func perform(
        _ body: @escaping @MainActor (WatchAudioManager) -> Void
    ) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in body(WatchAudioManager.shared) }
        return .success
    }
}
