//
//  MockFramework+Audio.swift
//  AudiobookReaderTests
//
//  Split from MockFramework.swift (mock audio engine and CUE parser)
//

import Foundation
import AVFoundation
@testable import AudiobookReader

// MARK: - Mock Audio Engine
class MockAudioEngine: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 3600
    @Published var isPlaying: Bool = false
    @Published var isReady: Bool = true
    @Published var playbackRate: Float = 1.0
    @Published var currentChapterIndex: Int = 0
    
    var audiobook: AudiobookModel?
    var shouldFailOperations = false
    var mockChapters: [ChapterModel] = []
    
    private var playbackTimer: Timer?
    
    func loadAudio(url: URL) {
        guard !shouldFailOperations else { return }
        
        // Mock loading from URL
        self.isReady = true
        self.duration = 3600 // Default 1 hour
        self.currentTime = 0
    }
    
    func loadAudiobook(_ audiobook: AudiobookModel) throws {
        guard !shouldFailOperations else {
            throw AudiobookError.fileNotFound("Mock error for testing")
        }
        
        self.audiobook = audiobook
        self.duration = audiobook.duration
        self.currentTime = audiobook.currentPosition
        self.isReady = true
        
        // Create mock chapters if audiobook has chapters
        mockChapters = audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }
    
    func play() {
        guard !shouldFailOperations && isReady else { return }
        
        isPlaying = true
        startPlaybackTimer()
    }
    
    func startPlayback() {
        play()
    }
    
    func startPlaybook() {
        play()
    }
    
    func pause() {
        isPlaying = false
        stopPlaybackTimer()
    }
    
    func pausePlayback() {
        pause()
    }
    
    func resumePlayback() {
        guard !shouldFailOperations && isReady else { return }
        
        isPlaying = true
        startPlaybackTimer()
    }
    
    func stop() {
        isPlaying = false
        stopPlaybackTimer()
        currentTime = 0
    }
    
    func stopPlayback() {
        stop()
    }
    
    func stopPlaybook() {
        stop()
    }
    
    func seek(to time: TimeInterval) {
        currentTime = max(0, min(time, duration))
        updateCurrentChapter()
    }
    
    func skipForward(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }
    
    func skipBackward(_ seconds: TimeInterval) {
        seek(to: currentTime - seconds)
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
    }
    
    func skipToChapter(_ chapterIndex: Int) {
        guard !mockChapters.isEmpty, chapterIndex >= 0, chapterIndex < mockChapters.count else { return }
        
        currentChapterIndex = chapterIndex
        seek(to: mockChapters[chapterIndex].startTime)
    }
    
    func nextChapter() {
        guard !mockChapters.isEmpty else { return }
        
        let nextIndex = min(currentChapterIndex + 1, mockChapters.count - 1)
        if nextIndex != currentChapterIndex {
            currentChapterIndex = nextIndex
            seek(to: mockChapters[nextIndex].startTime)
        }
    }
    
    func previousChapter() {
        guard !mockChapters.isEmpty else { return }
        
        let prevIndex = max(currentChapterIndex - 1, 0)
        if prevIndex != currentChapterIndex {
            currentChapterIndex = prevIndex
            seek(to: mockChapters[prevIndex].startTime)
        }
    }
    
    func cleanup() {
        stopPlaybackTimer()
        audiobook = nil
        mockChapters.removeAll()
        isReady = false
    }
    
    // MARK: - Private Helpers
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            
            self.currentTime += 0.1 * Double(self.playbackRate)
            
            if self.currentTime >= self.duration {
                self.currentTime = self.duration
                self.pausePlayback()
            }
            
            self.updateCurrentChapter()
        }
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updateCurrentChapter() {
        guard !mockChapters.isEmpty else { return }
        
        for (index, chapter) in mockChapters.enumerated() {
            if currentTime >= chapter.startTime && currentTime < chapter.endTime {
                currentChapterIndex = index
                break
            }
        }
    }
    
    func reset() {
        stopPlaybackTimer()
        currentTime = 0
        duration = 3600
        isPlaying = false
        isReady = true
        playbackRate = 1.0
        currentChapterIndex = 0
        audiobook = nil
        mockChapters.removeAll()
        shouldFailOperations = false
    }
}

// MARK: - Mock CUE Parser
class MockCUEParser {
    static var shouldFailParsing = false
    static var mockParseResult: CUEParseResult?
    
    struct CUEParseResult {
        let chapters: [CUEChapter]
        let audioFileName: String?
        let metadata: [String: String]
    }
    
    struct CUEChapter {
        let title: String
        let startTime: TimeInterval
        let endTime: TimeInterval?
        let trackNumber: Int
    }
    
    static func parseCUE(from url: URL) -> CUEParseResult? {
        guard !shouldFailParsing else { return nil }
        
        if let result = mockParseResult {
            return result
        }
        
        // Return default mock result
        return CUEParseResult(
            chapters: [
                CUEChapter(title: "Chapter 1", startTime: 0, endTime: 1800, trackNumber: 1),
                CUEChapter(title: "Chapter 2", startTime: 1800, endTime: 3600, trackNumber: 2)
            ],
            audioFileName: "audiobook.mp3",
            metadata: ["TITLE": "Test Audiobook", "PERFORMER": "Test Author"]
        )
    }
    
    static func reset() {
        shouldFailParsing = false
        mockParseResult = nil
    }
}
