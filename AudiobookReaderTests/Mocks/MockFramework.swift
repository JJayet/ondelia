//
//  MockFramework.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Foundation
import AVFoundation
@testable import AudiobookReader

// MARK: - Mock AVAudioSession
class MockAVAudioSession {
    static var shouldFailSetup = false
    static var preferredSampleRate: Double = 44100.0
    static var currentRoute: AVAudioSessionRouteDescription = AVAudioSessionRouteDescription()
    static var isOtherAudioPlaying = false
    
    static func reset() {
        shouldFailSetup = false
        preferredSampleRate = 44100.0
        isOtherAudioPlaying = false
    }
}

// MARK: - Mock FileManager
class MockFileManager {
    static var mockFileExists: [String: Bool] = [:]
    static var mockDirectoryContents: [String: [URL]] = [:]
    static var mockFileSize: [String: Int64] = [:]
    static var shouldFailFileOperations = false
    
    static func reset() {
        mockFileExists.removeAll()
        mockDirectoryContents.removeAll()
        mockFileSize.removeAll()
        shouldFailFileOperations = false
    }
    
    static func setFileExists(_ path: String, exists: Bool) {
        mockFileExists[path] = exists
    }
    
    static func setDirectoryContents(_ path: String, contents: [URL]) {
        mockDirectoryContents[path] = contents
    }
    
    static func setFileSize(_ path: String, size: Int64) {
        mockFileSize[path] = size
    }
}

// MARK: - Mock AVURLAsset
class MockAVURLAsset {
    let mockDuration: TimeInterval
    let mockMetadata: [AVMetadataItem]
    let mockIsPlayable: Bool
    let mockTracks: [MockAVAssetTrack]
    let url: URL
    
    init(
        url: URL,
        duration: TimeInterval = 3600.0,
        metadata: [AVMetadataItem] = [],
        isPlayable: Bool = true,
        tracks: [MockAVAssetTrack] = []
    ) {
        self.url = url
        self.mockDuration = duration
        self.mockMetadata = metadata
        self.mockIsPlayable = isPlayable
        self.mockTracks = tracks.isEmpty ? [MockAVAssetTrack()] : tracks
    }
    
    var duration: CMTime {
        return CMTime(seconds: mockDuration, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    }
    
    var metadata: [AVMetadataItem] {
        return mockMetadata
    }
    
    var isPlayable: Bool {
        return mockIsPlayable
    }
    
    func tracks(withMediaType mediaType: AVMediaType) -> [MockAVAssetTrack] {
        return mockTracks.filter { $0.mediaType == mediaType }
    }
}

// MARK: - Mock AVAssetTrack
class MockAVAssetTrack {
    let mediaType: AVMediaType
    let formatDescriptions: [Any]
    let isEnabled: Bool
    
    init(
        mediaType: AVMediaType = .audio,
        formatDescriptions: [Any] = [],
        isEnabled: Bool = true
    ) {
        self.mediaType = mediaType
        self.formatDescriptions = formatDescriptions
        self.isEnabled = isEnabled
    }
}

// MARK: - Mock AVPlayer
class MockAVPlayer {
    var mockCurrentItem: MockAVPlayerItem?
    var mockRate: Float = 0.0
    var mockTimeObservers: [Any] = []
    var shouldFailToPlay = false
    
    func replaceCurrentItem(with item: MockAVPlayerItem?) {
        mockCurrentItem = item
    }
    
    func play() {
        guard !shouldFailToPlay else { return }
        mockRate = 1.0
    }
    
    func pause() {
        mockRate = 0.0
    }
    
    func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        // Simulate async seek operation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            completionHandler(!self.shouldFailToPlay)
        }
    }
    
    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping (CMTime) -> Void
    ) -> Any {
        let observer = UUID()
        mockTimeObservers.append(observer)
        return observer
    }
    
    func removeTimeObserver(_ observer: Any) {
        if let index = mockTimeObservers.firstIndex(where: { $0 as? UUID == observer as? UUID }) {
            mockTimeObservers.remove(at: index)
        }
    }
    
    func reset() {
        mockCurrentItem = nil
        mockRate = 0.0
        mockTimeObservers.removeAll()
        shouldFailToPlay = false
    }
}

// MARK: - Mock AVPlayerItem
class MockAVPlayerItem {
    let asset: MockAVURLAsset
    var status: AVPlayerItem.Status = .readyToPlay
    var duration: CMTime { return asset.duration }
    var currentTime: CMTime = .zero
    var canStepForward = true
    var canStepBackward = true
    
    init(asset: MockAVURLAsset, status: AVPlayerItem.Status = .readyToPlay) {
        self.asset = asset
        self.status = status
    }
    
    func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        currentTime = time
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            completionHandler(true)
        }
    }
}

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

// MARK: - Test Utilities
class TestDataFactory {
    
    static func createMockAudioFile(named name: String, duration: TimeInterval = 3600) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).m4a")
        
        // Create empty file for testing
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    static func createMockCUEFile(named name: String, content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).cue")
        
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    static func createMockZIPFile(named name: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).zip")
        
        // Create mock ZIP file with empty data
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    static func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        for item in (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }
}