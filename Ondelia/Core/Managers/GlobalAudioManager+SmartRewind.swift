import Foundation

// MARK: - Smart rewind
//
// Resuming rewinds by an amount that grows with the length of the pause, so a book picked back
// up the next morning starts a sentence earlier instead of mid-word.
extension GlobalAudioManager {
    /// Longest pause that still lengthens the rewind. Past an hour, a night and a week are the
    /// same thing: the listener has lost the thread either way.
    static let smartRewindThreshold: TimeInterval = 60 * 60
    /// The rewind a long pause earns. Roughly a sentence of narration.
    static let smartRewindMaxInterval: TimeInterval = 30
    /// Every resume gives back at least this much, so tapping play twice replays a word or two.
    static let smartRewindMinimum: TimeInterval = 2

    /// How far to rewind, given how long the book sat paused.
    ///
    /// Pure, so the curve can be checked without a player: `away` is the pause in seconds and
    /// `timeInChapter` how far into the current chapter playback stopped.
    static func smartRewindAmount(away: TimeInterval, timeInChapter: TimeInterval) -> TimeInterval {
        guard away.isFinite, timeInChapter.isFinite else { return 0 }
        let elapsed = max(away, 0)
        // Quartic ease-out: most of the rewind is earned in the first few minutes, then it
        // flattens off — the difference between a ten-minute break and an hour is small, while
        // the difference between five seconds and two minutes is the whole point.
        let progress = min(elapsed, smartRewindThreshold) / smartRewindThreshold
        let eased = 1 - pow(1 - progress, 4)
        let wanted = max(eased * smartRewindMaxInterval, smartRewindMinimum)
        // Never cross back into the previous chapter, and never rewind further than the pause
        // itself lasted: a two-second pause has no two seconds of lost context to give back.
        return max(min(wanted, max(timeInChapter, 0), elapsed), 0)
    }

    /// Applies the rewind to the loaded player. Called from `resumePlayback`, before playback
    /// starts, so the seek is inaudible.
    ///
    /// The pause length comes from `lastPlayed`, which the progress timer writes every few
    /// seconds while playing and once more on pause — so it already marks the moment playback
    /// stopped. Nothing extra to store, and it survives a relaunch, since it lives in the library.
    func applySmartRewind() {
        guard ThemeManager.shared.smartRewindEnabled,
              let player,
              let audiobook = currentAudiobook
        else { return }

        let now = player.currentTime
        let chapterStart = audiobook.sortedChapters.last { $0.startTime <= now }?.startTime ?? 0
        // A book that has never been played holds `.distantPast`, which the chapter clamp turns
        // into no rewind at all: it is sitting at position zero.
        let rewind = Self.smartRewindAmount(
            away: Date().timeIntervalSince(audiobook.lastPlayed),
            timeInChapter: now - chapterStart
        )
        guard rewind > 0 else { return }
        player.seek(to: now - rewind)
    }
}
