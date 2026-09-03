import Foundation

extension GlobalAudioManager {
    func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleepTimeRemaining -= 1
                guard self.sleepTimeRemaining <= 0 else { return }
                self.pausePlayback()
                self.cancelSleepTimer()
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
