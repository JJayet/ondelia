import Foundation

extension GlobalAudioManager {
    func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                self.sleepTimeRemaining -= 1
                if self.sleepTimeRemaining <= 0 {
                    self.pausePlayback()
                    timer.invalidate()
                    self.sleepTimer = nil
                    self.sleepTimeRemaining = 0
                }
            }
        }
    }

    /// Stops at the end of the chapter containing the current position. No chapters: 15 minutes.
    func setSleepTimerEndOfChapter() {
        let now = getCurrentTime()
        let chapter = currentAudiobook?.chapters
            .sorted { $0.chapterNumber < $1.chapterNumber }
            .first { now >= $0.startTime && now < $0.endTime }
        let remaining = chapter.map { max($0.endTime - now, 60) } ?? 900
        setSleepTimer(remaining)
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimeRemaining = 0
    }
}
