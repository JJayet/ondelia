import Foundation

extension GlobalAudioManager {
    /// How often a playing book writes its position to the library.
    private static let progressSaveInterval: TimeInterval = 5

    /// Starts writing the playback position to the library while a book plays.
    ///
    /// Owned here rather than in `PlayerViewModel`, because playback outlives the player screen:
    /// the mini player, the lock screen, CarPlay and App Shortcuts all play with no view ticking.
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
                // Refreshes the widget and Live Activity data even with the player screen closed.
                // No timeline reload: the widget interpolates from `updatedAt` and the rate, and
                // reloading every few seconds burns the widget's refresh budget for nothing.
                self.publishPlaybackSnapshot()
            }
        }
    }

    func stopProgressPersistence() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Writes the current position, unless doing so would overwrite a real position with a
    /// meaningless one: a book that is still loading reads back as time zero until its seek lands.
    func persistProgress() {
        guard let audiobook = currentAudiobook, isReady, !isLoading else { return }
        // Playback can start before the store finishes loading (an App Shortcut on a cold launch).
        guard AudiobookManager.shared.swiftDataController.isLoaded else { return }
        let currentTime = getCurrentTime()
        guard currentTime > 0 else { return }
        AudiobookManager.shared.updateProgress(for: audiobook, currentTime: currentTime)
    }

    /// One place for "playback state changed": persist, keep the timer honest, and refresh the
    /// widgets and Live Activity, which used to only happen while the player screen was open.
    func playbackStateDidChange() {
        if playbackState == .playing {
            startProgressPersistence()
        } else {
            stopProgressPersistence()
            persistProgress()
        }
        // A state change is worth a real timeline reload; the periodic tick above is not.
        publishPlaybackSnapshot(reloadTimeline: true)
    }
}
