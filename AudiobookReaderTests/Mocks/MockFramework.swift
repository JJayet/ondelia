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
