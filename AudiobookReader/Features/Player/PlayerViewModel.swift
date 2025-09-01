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
    
    // Convert computed properties to @Published to avoid method calls on every access
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentChapter: ChapterModel? = nil

    private var sleepTimer: Timer?
    private var progressTimer: Timer?
    private var hasMarkedCompletion = false
    private var lastProgressSave: Date = .distantPast

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
        updatePublishedProperties() // Initial update
        startProgressTimer()
    }

    func autoPlayIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.audioManager.playbackState != .playing {
                self.audioManager.startPlayback()
                self.updatePublishedProperties() // Update after state change
            }
        }
    }
    
    func cleanup() {
        stopProgressTimer()
        cancelSleepTimer()
    }

    private func updatePublishedProperties() {
        // Update @Published properties instead of computing them on every access
        self.isPlaying = (audioManager.playbackState == .playing)
        self.currentTime = audioManager.getCurrentTime()
        self.duration = audioManager.getDuration()
        self.playbackRate = audioManager.getPlaybackRate()
        self.updateCurrentChapter()
    }
    
    private func updateCurrentChapter() {
        let chapters = audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        let currentTime = self.currentTime
        self.currentChapter = chapters.first { chapter in
            currentTime >= chapter.startTime && currentTime < chapter.endTime
        } ?? chapters.first { chapter in
            currentTime >= chapter.startTime
        }
    }

    func onTick() {
        // Always update published properties first to ensure UI stays in sync
        updatePublishedProperties()
        
        // Only skip further processing if manually seeking
        guard !isSeekingManually else { return }
        
        // Only update progress and statistics if actually playing
        if isPlaying {
            // Reduce SwiftData write frequency to avoid UI churn
            let now = Date()
            if now.timeIntervalSince(lastProgressSave) >= 3 {
                audiobookManager.updateProgress(for: audiobook, currentTime: currentTime)
                lastProgressSave = now
            }
            statistics.addListeningTime(1, playbackRate: playbackRate)

            if audiobook.isFinished && !hasMarkedCompletion {
                statistics.markBookCompleted()
                hasMarkedCompletion = true
            }
        }
    }

    // MARK: - Sleep Timer
    func setSleepTimer(_ seconds: TimeInterval) {
        cancelSleepTimer()
        sleepTimeRemaining = seconds

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            Task { @MainActor in
                self.sleepTimeRemaining -= 1
                if self.sleepTimeRemaining <= 0 {
                    self.audioManager.pausePlayback()
                    self.updatePublishedProperties() // Update after state change
                    timer.invalidate()
                    self.sleepTimer = nil
                }
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
    
    // MARK: - Progress Timer Management
    private func startProgressTimer() {
        stopProgressTimer()
        // Use 1 second intervals for smooth progress bar updates
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
