import Foundation

extension GlobalAudioManager {
    /// UserDefaults keys. The toggle is bound from Settings; the other two remember the last
    /// timer chosen so the automatic one repeats it.
    static let autoSleepTimerKey = "playback.autoSleepTimer"
    static let lastSleepTimerSecondsKey = "sleepTimer.lastSeconds"
    static let lastSleepTimerEndOfChapterKey = "sleepTimer.lastEndOfChapter"

    func setSleepTimer(_ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: Self.lastSleepTimerSecondsKey)
        UserDefaults.standard.set(false, forKey: Self.lastSleepTimerEndOfChapterKey)
        startSleepTimer(seconds)
    }

    /// Starts the remembered timer when the setting is on and none is running. Called on every
    /// play, so a timer that already fired is set again on the next resume.
    func startAutomaticSleepTimerIfEnabled() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.autoSleepTimerKey), sleepTimer == nil else { return }
        if defaults.bool(forKey: Self.lastSleepTimerEndOfChapterKey) {
            setSleepTimerEndOfChapter()
            return
        }
        let seconds = defaults.object(forKey: Self.lastSleepTimerSecondsKey) as? TimeInterval
        setSleepTimer(seconds ?? 900)
    }

    private func startSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // An end-of-chapter timer follows the book, not the clock: a speed change or a
                // seek changes how long the rest of the chapter takes.
                if let end = self.sleepChapterEnd {
                    self.sleepTimeRemaining = self.sleepSecondsUntil(end)
                } else {
                    self.sleepTimeRemaining -= 1
                }
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
    ///
    /// The chapter's end is a position in the book, not a number of seconds on a clock: at 2x it
    /// arrives in half the time, and a seek or a speed change moves it again. So the boundary is
    /// remembered and the countdown recomputed from it on every tick.
    func setSleepTimerEndOfChapter() {
        UserDefaults.standard.set(true, forKey: Self.lastSleepTimerEndOfChapterKey)
        let now = getCurrentTime()
        guard let chapter = currentAudiobook?.sortedChapters
            .first(where: { now >= $0.startTime && now < $0.endTime }) else {
            startSleepTimer(900)
            return
        }
        startSleepTimer(sleepSecondsUntil(chapter.endTime))
        sleepChapterEnd = chapter.endTime
    }

    /// Wall-clock seconds until a position in the book, at the speed playing now.
    func sleepSecondsUntil(_ position: TimeInterval) -> TimeInterval {
        let rate = Double(getPlaybackRate())
        let remaining = max(position - getCurrentTime(), 0)
        return rate > 0 ? remaining / rate : remaining
    }

    static let sleepFadeDuration: TimeInterval = 10

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimeRemaining = 0
        sleepChapterEnd = nil
        // Whatever the fade left behind, the next play starts at full volume.
        player?.setVolume(1)
    }
}
