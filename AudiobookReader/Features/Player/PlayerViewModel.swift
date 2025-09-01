import Foundation
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    let audiobook: AudiobookModel
    private let audioManager: any AudioManagerProtocol
    private let audiobookManager: AudiobookManagerProtocol
    private let statistics: ReadingStatistics

    @Published var isSeekingManually = false
    @Published var sleepTimeRemaining: TimeInterval = 0

    private var sleepTimer: Timer?
    private var hasMarkedCompletion = false

    init(audiobook: AudiobookModel,
         dependencies: AudiobookDependencies,
         statistics: ReadingStatistics) {
        self.audiobook = audiobook
        self.audioManager = dependencies.audioManager
        self.audiobookManager = dependencies.audiobookManager
        self.statistics = statistics
    }

    // MARK: - Derived State
    var isPlaying: Bool { (audioManager.playbackState == .playing) }
    var currentTime: TimeInterval { audioManager.getCurrentTime() }
    var duration: TimeInterval { audioManager.getDuration() }
    var playbackRate: Float { audioManager.getPlaybackRate() }

    // MARK: - Lifecycle
    func load() {
        audioManager.loadAudiobook(audiobook)
    }

    func autoPlayIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.audioManager.playbackState != .playing {
                self.audioManager.startPlayback()
            }
        }
    }

    func onTick() {
        guard !isSeekingManually, isPlaying else { return }
        let time = audioManager.getCurrentTime()
        audiobookManager.updateProgress(for: audiobook, currentTime: time)
        statistics.addListeningTime(1, playbackRate: playbackRate)

        if audiobook.isFinished && !hasMarkedCompletion {
            statistics.markBookCompleted()
            hasMarkedCompletion = true
        }
    }

    // MARK: - Sleep Timer
    func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            self.sleepTimeRemaining -= 1
            if self.sleepTimeRemaining <= 0 {
                (self.audioManager).pausePlayback()
                timer.invalidate()
                self.sleepTimer = nil
            }
        }
    }

    func setSleepTimerEndOfChapter(currentChapter: ChapterModel?, currentTime: TimeInterval) {
        guard let currentChapter else { return }
        let remaining = max(currentChapter.endTime - currentTime, 60) // Min 1 minute
        setSleepTimer(remaining)
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimeRemaining = 0
    }
}

