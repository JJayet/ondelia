import Foundation
import SwiftUI

// MARK: - Playback controls and helpers
//
// One player means these are all plain forwarding now. Each of them used to branch on
// `useMultiFileEngine` and address one of two engines.
extension GlobalAudioManager {
    func pausePlayback() {
        player?.pause()
        playbackState = .paused
        playbackStateDidChange()
    }

    func resumePlayback() {
        guard let player else {
            // Nothing to resume yet: remember the intent so the load can honour it.
            if isLoading { pendingAutoplay = true }
            return
        }
        player.play()
        showMiniPlayer = true
        playbackState = .playing
        playbackStateDidChange()
    }

    func startPlayback() {
        resumePlayback()
    }

    func stopPlayback() {
        pendingAutoplay = false
        player?.pause()
        showMiniPlayer = false
        playbackState = .stopped
        playbackStateDidChange()
    }

    func togglePlayback() {
        if isPlaying() {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func isPlaying() -> Bool { player?.isPlaying ?? false }
    func getCurrentTime() -> TimeInterval { player?.currentTime ?? 0 }
    func getDuration() -> TimeInterval { player?.duration ?? 0 }
    func getPlaybackRate() -> Float { player?.playbackRate ?? 1 }

    func setPlaybackRate(_ rate: Float) {
        rememberSpeed(rate)
        player?.setPlaybackRate(rate)
        playbackStateDidChange()
    }

    func skipForward(_ interval: TimeInterval) {
        player?.skipForward(interval)
        playbackStateDidChange()
    }

    func skipBackward(_ interval: TimeInterval) {
        player?.skipBackward(interval)
        playbackStateDidChange()
    }

    func seek(to time: TimeInterval) {
        player?.seek(to: time)
        // A deliberate jump is worth writing straight away rather than waiting for the save timer.
        persistProgress()
        playbackStateDidChange()
    }

    // MARK: - Now Playing Snapshot
    func publishPlaybackSnapshot(reloadTimeline: Bool = false) {
        NowPlayingSharedStore.write(
            audiobook: currentAudiobook,
            isPlaying: playbackState == .playing,
            currentTime: getCurrentTime(),
            duration: getDuration(),
            coverImageData: currentAudiobook?.coverImageData,
            playbackRate: getPlaybackRate(),
            reloadTimeline: reloadTimeline
        )
    }

    // MARK: - Utility Functions
    func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
