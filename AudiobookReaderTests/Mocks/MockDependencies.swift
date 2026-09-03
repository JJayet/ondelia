//
//  MockDependencies.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Foundation
import SwiftUI
import SwiftData
import XCTest
@testable import AudiobookReader

// MARK: - Mock Dependencies Container
class MockDependencies: AudiobookDependencies {
    let audioManager: any AudioManagerProtocol
    let audiobookManager: AudiobookManagerProtocol
    // Theme and statistics are plain value holders, so a test gets real ones. Only audio and
    // the library have side effects worth substituting.
    let themeManager = ThemeManager.shared
    let readingStatistics = ReadingStatistics()
    let swiftDataController: SwiftDataController

    init(
        audioManager: (any AudioManagerProtocol)? = nil,
        audiobookManager: AudiobookManagerProtocol? = nil,
        swiftDataController: SwiftDataController? = nil
    ) {
        self.audioManager = audioManager ?? MockGlobalAudioManager()
        self.audiobookManager = audiobookManager ?? MockAudiobookManager()
        self.swiftDataController = swiftDataController ?? SwiftDataController.preview
    }
}

// MARK: - Mock Audio Manager for Testing
@Observable
class MockAudioManager: AudioManagerProtocol {
    var playbackState: GlobalAudioManager.PlaybackState = .stopped
    var showMiniPlayer: Bool = false
    var currentAudiobook: AudiobookModel? = nil
    var isLoading: Bool = false
    var isReady: Bool = true
    
    // Mock data
    private var mockCurrentTime: TimeInterval = 0
    private var mockDuration: TimeInterval = 3600
    private var mockPlaybackRate: Float = 1.0
    
    func loadAudiobook(_ audiobook: AudiobookModel) {
        currentAudiobook = audiobook
        isReady = true
        showMiniPlayer = true
    }
    
    func startPlayback() {
        playbackState = .playing
    }
    
    func pausePlayback() {
        playbackState = .paused
    }
    
    func resumePlayback() {
        playbackState = .playing
    }
    
    func stopPlayback() {
        playbackState = .stopped
        showMiniPlayer = false
        mockCurrentTime = 0
    }
    
    func togglePlayback() {
        switch playbackState {
        case .playing:
            pausePlayback()
        case .paused, .stopped:
            resumePlayback()
        case .loading, .failed:
            break
        }
    }
    
    func isPlaying() -> Bool {
        return playbackState == .playing
    }
    
    func getCurrentTime() -> TimeInterval {
        return mockCurrentTime
    }
    
    func getDuration() -> TimeInterval {
        return mockDuration
    }
    
    func getPlaybackRate() -> Float {
        return mockPlaybackRate
    }
    
    func setPlaybackRate(_ rate: Float) {
        mockPlaybackRate = rate
    }
    
    func skipForward(_ seconds: TimeInterval) {
        mockCurrentTime = min(mockCurrentTime + seconds, mockDuration)
    }
    
    func skipBackward(_ seconds: TimeInterval) {
        mockCurrentTime = max(mockCurrentTime - seconds, 0)
    }
    
    func seek(to time: TimeInterval) {
        mockCurrentTime = max(0, min(time, mockDuration))
    }

    var sleepTimeRemaining: TimeInterval = 0
    func setSleepTimer(_ seconds: TimeInterval) { sleepTimeRemaining = seconds }
    func setSleepTimerEndOfChapter() { sleepTimeRemaining = 60 }
    func cancelSleepTimer() { sleepTimeRemaining = 0 }
    
    func setMockDuration(_ duration: TimeInterval) {
        mockDuration = duration
    }
    
    func setMockCurrentTime(_ time: TimeInterval) {
        mockCurrentTime = time
    }
}

// MARK: - Mock Audiobook for Testing  
class MockAudiobook {
    var title: String
    var author: String
    var duration: TimeInterval
    
    init(title: String = "Test Audiobook", author: String = "Test Author", duration: TimeInterval = 3600) {
        self.title = title
        self.author = author
        self.duration = duration
    }
}