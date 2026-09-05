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
        playbackState = .playing
        playbackStateDidChange()
        // Feeds the system's media suggestions — the row of covers in Control Center.
        if let currentAudiobook {
            MediaIntentDonations.donatePlayback(of: currentAudiobook)
        }
    }

    func startPlayback() {
        resumePlayback()
    }

    func stopPlayback() {
        pendingAutoplay = false
        player?.pause()
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

    /// Defaults to the interval chosen in Settings, so every caller that has no interval of
    /// its own — mini player, widget, App Intents — follows the setting instead of a literal.
    func skipForward(_ interval: TimeInterval = ThemeManager.shared.skipInterval.seconds) {
        player?.skipForward(interval)
        playbackStateDidChange()
    }

    func skipBackward(_ interval: TimeInterval = ThemeManager.shared.skipInterval.seconds) {
        player?.skipBackward(interval)
        playbackStateDidChange()
    }

    /// Start of the next chapter. Does nothing on the last one, and nothing without chapters.
    func skipToNextChapter() {
        let now = getCurrentTime()
        guard let next = currentAudiobook?.sortedChapters.first(where: { $0.startTime > now + 1 })
        else { return }
        seek(to: next.startTime)
    }

    /// Start of the current chapter, or of the previous one when already at the top of this
    /// one — the same rule every music player uses for its back button.
    func skipToPreviousChapter() {
        let chapters = currentAudiobook?.sortedChapters ?? []
        let now = getCurrentTime()
        guard let current = chapters.last(where: { $0.startTime <= now }) else {
            seek(to: 0)
            return
        }
        guard now - current.startTime <= 3 else {
            seek(to: current.startTime)
            return
        }
        let index = chapters.firstIndex { $0.id == current.id } ?? 0
        seek(to: index > 0 ? chapters[index - 1].startTime : 0)
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
}
