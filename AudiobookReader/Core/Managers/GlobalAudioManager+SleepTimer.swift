import Foundation

extension GlobalAudioManager {
    func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleepTimeRemaining -= 1
                // Fade over the last 10 seconds: waking up to a mid-sentence cut is worse
                // than losing the last few words to a fade.
                if self.sleepTimeRemaining <= Self.sleepFadeDuration {
                    self.player?.setVolume(Float(max(self.sleepTimeRemaining, 0) / Self.sleepFadeDuration))
                }
                guard self.sleepTimeRemaining <= 0 else { return }
                self.pausePlayback()
                self.cancelSleepTimer()
            }
        }
    }

    /// Stops at the end of the chapter containing the current position. No chapters: 15 minutes.
    func setSleepTimerEndOfChapter() {
        let now = getCurrentTime()
        let chapter = currentAudiobook?.sortedChapters
            .first { now >= $0.startTime && now < $0.endTime }
        let remaining = chapter.map { max($0.endTime - now, 60) } ?? 900
        setSleepTimer(remaining)
    }

    static let sleepFadeDuration: TimeInterval = 10

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimeRemaining = 0
        // Whatever the fade left behind, the next play starts at full volume.
        player?.setVolume(1)
    }
}
