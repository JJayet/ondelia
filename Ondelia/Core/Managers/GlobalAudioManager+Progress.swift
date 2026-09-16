import Foundation

extension GlobalAudioManager {
    /// How often a playing book writes its position to the library.
    private static let progressSaveInterval: TimeInterval = 5

    /// Starts writing the playback position to the library while a book plays.
    ///
    /// Owned here rather than in `PlayerViewModel`, because playback outlives the player screen:
    /// the mini player, the lock screen and App Shortcuts all play with no view ticking.
    /// Driven from the manager, a kill or a crash costs at most `progressSaveInterval` seconds
    /// instead of everything since the app was last backgrounded.
    func startProgressPersistence() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(
            withTimeInterval: Self.progressSaveInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.persistProgress()
                self.accrueListening(Self.progressSaveInterval)
                // Refreshes the widget data even with the player screen closed.
                // No timeline reload: the widget interpolates from `updatedAt` and the rate, and
                // reloading every few seconds burns the widget's refresh budget for nothing.
                self.publishPlaybackSnapshot()
            }
        }
    }

    /// Counts time spent listening. Lives here, next to progress, for the same reason: this
    /// timer runs whenever a book plays, while `PlayerViewModel`'s tick stopped with the player
    /// screen — so the mini player and the lock screen both counted as no listening.
    func accrueListening(_ seconds: TimeInterval, into statistics: ReadingStatistics = .shared) {
        guard let audiobook = currentAudiobook else { return }
        statistics.addListeningTime(seconds, for: audiobook)
    }

    func stopProgressPersistence() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Writes the current position. `isReady && !isLoading` already excludes what a zero check
    /// was guarding — a book still loading reads back as time zero until its seek lands — so a
    /// zero reaching here means the listener seeked to the start, and has to be persisted.
    func persistProgress() {
        guard let audiobook = currentAudiobook, isReady, !isLoading else { return }
        // Playback can start before the store finishes loading (an App Shortcut on a cold launch).
        guard AudiobookManager.shared.swiftDataController.isLoaded else { return }
        AudiobookManager.shared.updateProgress(for: audiobook, currentTime: getCurrentTime())
        WatchSyncService.shared.phoneDidPersistProgress(for: audiobook)
    }

    /// One place for "playback state changed": persist, keep the timer honest, and refresh the
    /// widgets, which used to only happen while the player screen was open.
    func playbackStateDidChange() {
        if playbackState == .playing {
            startProgressPersistence()
        } else {
            stopProgressPersistence()
            persistProgress()
        }
        // Position and rate, so the lock screen and Control Center extrapolate from the right
        // point instead of the one the book was loaded at.
        updateNowPlayingInfo()
        // A state change is worth a real timeline reload; the periodic tick above is not.
        publishPlaybackSnapshot(reloadTimeline: true)
        WatchSyncService.shared.phonePlaybackStateDidChange()
    }
}
