import Foundation
import SwiftUI

@MainActor
@Observable
final class PlayerViewModel {
    let audiobook: AudiobookModel
    private let audioManager: any AudioManagerProtocol
    private let audiobookManager: AudiobookManagerProtocol
    private let statistics: ReadingStatistics

    var isSeekingManually = false

    /// Read straight through to the audio manager instead of mirroring its state on a timer.
    /// Observation tracks the engine properties these touch, so the player redraws whenever
    /// playback moves — at the engine's own 0.25s tick rather than a once-a-second copy.
    var isPlaying: Bool { audioManager.playbackState == .playing }
    var currentTime: TimeInterval { audioManager.getCurrentTime() }
    var duration: TimeInterval { audioManager.getDuration() }
    var playbackRate: Float { audioManager.getPlaybackRate() }
    var sleepTimeRemaining: TimeInterval { audioManager.sleepTimeRemaining }

    var currentChapter: ChapterModel? {
        let chapters = audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        let now = currentTime
        return chapters.first { now >= $0.startTime && now < $0.endTime }
            ?? chapters.last { now >= $0.startTime }
    }

    /// Listening time accrues by the clock, not by redraws, so this tick stays.
    private var statisticsTimer: Timer?
    private var hasMarkedCompletion = false

    init(audiobook: AudiobookModel,
         dependencies: AudiobookDependencies,
         statistics: ReadingStatistics) {
        self.audiobook = audiobook
        self.audioManager = dependencies.audioManager
        self.audiobookManager = dependencies.audiobookManager
        self.statistics = statistics
    }

    // MARK: - Lifecycle
    func load() {
        audioManager.loadAudiobook(audiobook)
        startStatisticsTimer()
    }

    func autoPlayIfNeeded() {
        if audioManager.playbackState != .playing {
            // GlobalAudioManager queues this request while an engine is still loading.
            audioManager.startPlayback()
        }
    }

    func cleanup() {
        stopStatisticsTimer()
    }

    func onTick() {
        guard !isSeekingManually, isPlaying else { return }
        statistics.addListeningTime(1, playbackRate: playbackRate)

        if audiobook.isFinished && !hasMarkedCompletion {
            statistics.markBookCompleted()
            hasMarkedCompletion = true
        }
    }

    // MARK: - Sleep Timer (owned by audio manager so App Shortcuts can set it)
    func setSleepTimer(_ seconds: TimeInterval) {
        audioManager.setSleepTimer(seconds)
    }

    func setSleepTimerEndOfChapter() {
        audioManager.setSleepTimerEndOfChapter()
    }

    func cancelSleepTimer() {
        audioManager.cancelSleepTimer()
    }

    // MARK: - Statistics Timer Management
    private func startStatisticsTimer() {
        stopStatisticsTimer()
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
    }

    private func stopStatisticsTimer() {
        statisticsTimer?.invalidate()
        statisticsTimer = nil
    }
}
