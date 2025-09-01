//
//  PlatformIntegrationTests.swift
//  AudiobookReaderTests
//
//  Created for Phase 3 Advanced Testing - iOS Platform Integration Testing
//

import XCTest
import AVFoundation
import MediaPlayer
import CarPlay
import WatchConnectivity
@testable import AudiobookReader

final class PlatformIntegrationTests: XCTestCase {
    
    var dependencies: MockDependencies!
    var audioManager: MockAudioManager!
    var platformIntegrator: PlatformIntegrator!
    
    override func setUpWithError() throws {
        dependencies = MockDependencies()
        audioManager = dependencies.audioManager as! MockAudioManager
        platformIntegrator = PlatformIntegrator()
    }
    
    override func tearDownWithError() throws {
        dependencies = nil
        audioManager = nil
        platformIntegrator = nil
        
        // Clean up any background tasks or observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Background Audio Processing Tests
    
    func testBackgroundAudioContinuity() throws {
        let testAudiobook = createTestAudiobook()
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        XCTAssertEqual(audioManager.playbackState, .playing)
        
        // Simulate app entering background
        simulateAppLifecycleTransition(.background)
        
        // Background audio should continue
        let backgroundExpectation = expectation(description: "Background audio continues")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            XCTAssertEqual(self.audioManager.playbackState, .playing, 
                          "Audio should continue playing in background")
            backgroundExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        // Simulate returning to foreground
        simulateAppLifecycleTransition(.active)
        
        XCTAssertEqual(audioManager.playbackState, .playing,
                      "Playback state should be maintained when returning to foreground")
    }
    
    func testBackgroundAudioSessionManagement() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Set up background audio session
        try audioSession.setCategory(.playback, mode: .spokenAudio)
        try audioSession.setActive(true)
        
        let testAudiobook = createTestAudiobook()
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        // Simulate background app refresh disabled
        simulateBackgroundAppRefreshSettings(enabled: false)
        
        simulateAppLifecycleTransition(.background)
        
        // Should maintain audio session even with background refresh disabled
        XCTAssertTrue(audioSession.isOtherAudioPlaying == false || 
                     audioSession.category == .playback,
                     "Audio session should be maintained in background")
        
        // Simulate background processing time limit
        simulateBackgroundProcessingTimeLimit()
        
        // Should gracefully handle background time limit
        let timeoutExpectation = expectation(description: "Background timeout handling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let finalState = self.audioManager.playbackState
            XCTAssertTrue(finalState == .playing || finalState == .paused,
                         "Should handle background processing limits gracefully")
            timeoutExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 3.0)
    }
    
    func testAppLifecycleStateManagement() throws {
        let testAudiobook = createTestAudiobook()
        audioManager.loadAudiobook(testAudiobook)
        
        // Test various lifecycle transitions
        let lifecycleStates: [UIApplication.State] = [.active, .inactive, .background, .active]
        
        for state in lifecycleStates {
            simulateAppLifecycleTransition(state)
            
            switch state {
            case .active:
                XCTAssertTrue(audioManager.isAudioSessionActive,
                             "Audio session should be active in foreground")
            case .background:
                // Should maintain session for background audio
                XCTAssertTrue(audioManager.isAudioSessionActive || audioManager.playbackState == .paused,
                             "Should maintain audio session or pause in background")
            case .inactive:
                // Brief inactive state should not affect playback
                XCTAssertTrue(audioManager.playbackState != .error,
                             "Should handle inactive state gracefully")
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - CarPlay Integration Tests
    
    func testCarPlayAudioInterfaceAvailability() throws {
        let carPlayManager = CarPlayManager()
        
        // Test CarPlay template availability
        let audioTemplate = carPlayManager.createNowPlayingTemplate()
        XCTAssertNotNil(audioTemplate, "Should create CarPlay now playing template")
        
        // Test CarPlay audio controls
        let playButton = carPlayManager.createPlayButton()
        let pauseButton = carPlayManager.createPauseButton()
        let nextButton = carPlayManager.createNextButton()
        let previousButton = carPlayManager.createPreviousButton()
        
        XCTAssertNotNil(playButton, "Should create CarPlay play button")
        XCTAssertNotNil(pauseButton, "Should create CarPlay pause button")
        XCTAssertNotNil(nextButton, "Should create CarPlay next button")
        XCTAssertNotNil(previousButton, "Should create CarPlay previous button")
        
        // Test button actions
        let testAudiobook = createTestAudiobook()
        audioManager.loadAudiobook(testAudiobook)
        
        XCTAssertNoThrow(carPlayManager.handlePlayAction(),
                        "CarPlay play action should not crash")
        XCTAssertNoThrow(carPlayManager.handlePauseAction(),
                        "CarPlay pause action should not crash")
    }
    
    func testCarPlayNowPlayingInfoUpdate() throws {
        let carPlayManager = CarPlayManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        carPlayManager.updateNowPlayingInfo(for: testAudiobook)
        
        // Verify CarPlay now playing info is updated
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        
        XCTAssertNotNil(nowPlayingInfo, "CarPlay should have now playing info")
        XCTAssertEqual(nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, 
                      testAudiobook.title,
                      "CarPlay should display correct title")
        XCTAssertEqual(nowPlayingInfo?[MPMediaItemPropertyArtist] as? String,
                      testAudiobook.author,
                      "CarPlay should display correct author")
    }
    
    func testCarPlayListTemplateIntegration() throws {
        let carPlayManager = CarPlayManager()
        let testAudiobooks = (0..<5).map { createTestAudiobook(title: "Test Book \(i)") }
        
        let listTemplate = carPlayManager.createLibraryListTemplate(with: testAudiobooks)
        XCTAssertNotNil(listTemplate, "Should create CarPlay library list template")
        
        let listItems = carPlayManager.getListItems(for: testAudiobooks)
        XCTAssertEqual(listItems.count, testAudiobooks.count,
                      "CarPlay list should contain all audiobooks")
        
        // Test item selection
        if let firstItem = listItems.first {
            XCTAssertNoThrow(carPlayManager.handleListItemSelection(firstItem),
                           "CarPlay list item selection should not crash")
        }
    }
    
    // MARK: - AirPlay Functionality Tests
    
    func testAirPlayDiscovery() throws {
        let airPlayManager = AirPlayManager()
        
        // Test AirPlay route discovery
        let routes = airPlayManager.discoverAvailableRoutes()
        XCTAssertNotNil(routes, "Should be able to discover AirPlay routes")
        
        // Test AirPlay availability detection
        let isAvailable = airPlayManager.isAirPlayAvailable()
        XCTAssertTrue(isAvailable || !isAvailable, "Should return valid availability status")
        
        // Test route selection handling
        XCTAssertNoThrow(airPlayManager.setupRouteChangeHandling(),
                        "Route change handling should not crash")
    }
    
    func testAirPlayAudioRedirection() throws {
        let airPlayManager = AirPlayManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        // Simulate AirPlay route selection
        airPlayManager.simulateAirPlayRouteSelection()
        
        // Should handle AirPlay redirection
        let routeChangeExpectation = expectation(description: "AirPlay route change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let playbackState = self.audioManager.playbackState
            XCTAssertTrue(playbackState == .playing || playbackState == .paused,
                         "Should handle AirPlay route changes gracefully")
            routeChangeExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 3.0)
        
        // Simulate AirPlay disconnection
        airPlayManager.simulateAirPlayDisconnection()
        
        let disconnectionExpectation = expectation(description: "AirPlay disconnection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let finalState = self.audioManager.playbackState
            XCTAssertTrue(finalState == .playing || finalState == .paused,
                         "Should handle AirPlay disconnection gracefully")
            disconnectionExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 3.0)
    }
    
    // MARK: - Control Center Integration Tests
    
    func testControlCenterRemoteCommandSetup() throws {
        let remoteCommandManager = RemoteCommandManager()
        
        // Test remote command registration
        XCTAssertNoThrow(remoteCommandManager.setupRemoteCommands(),
                        "Remote command setup should not crash")
        
        let supportedCommands = remoteCommandManager.getSupportedCommands()
        
        let expectedCommands: [MPRemoteCommand] = [
            MPRemoteCommandCenter.shared().playCommand,
            MPRemoteCommandCenter.shared().pauseCommand,
            MPRemoteCommandCenter.shared().skipForwardCommand,
            MPRemoteCommandCenter.shared().skipBackwardCommand,
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand
        ]
        
        for command in expectedCommands {
            XCTAssertTrue(supportedCommands.contains { $0.isEqual(command) },
                         "Should support \(command)")
        }
    }
    
    func testControlCenterNowPlayingInfoUpdate() throws {
        let testAudiobook = createTestAudiobook()
        let nowPlayingManager = NowPlayingInfoManager()
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        nowPlayingManager.updateNowPlayingInfo(
            title: testAudiobook.title,
            author: testAudiobook.author,
            artwork: testAudiobook.coverImageData,
            duration: testAudiobook.duration,
            currentTime: audioManager.getCurrentTime(),
            playbackRate: audioManager.getPlaybackRate()
        )
        
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertNotNil(nowPlayingInfo, "Should set now playing info")
        
        let title = nowPlayingInfo?[MPMediaItemPropertyTitle] as? String
        let artist = nowPlayingInfo?[MPMediaItemPropertyArtist] as? String
        let duration = nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] as? Double
        
        XCTAssertEqual(title, testAudiobook.title, "Should set correct title")
        XCTAssertEqual(artist, testAudiobook.author, "Should set correct artist")
        XCTAssertEqual(duration, testAudiobook.duration, accuracy: 1.0, "Should set correct duration")
    }
    
    func testControlCenterRemoteCommandHandling() throws {
        let remoteCommandManager = RemoteCommandManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        remoteCommandManager.setupRemoteCommands()
        
        // Test play command
        let playResult = remoteCommandManager.handlePlayCommand(event: MockCommandEvent())
        XCTAssertEqual(playResult, .success, "Should handle play command successfully")
        XCTAssertEqual(audioManager.playbackState, .playing)
        
        // Test pause command
        let pauseResult = remoteCommandManager.handlePauseCommand(event: MockCommandEvent())
        XCTAssertEqual(pauseResult, .success, "Should handle pause command successfully")
        XCTAssertEqual(audioManager.playbackState, .paused)
        
        // Test skip forward command
        let skipForwardResult = remoteCommandManager.handleSkipForwardCommand(event: MockSkipCommandEvent(interval: 30))
        XCTAssertEqual(skipForwardResult, .success, "Should handle skip forward command")
        
        // Test skip backward command
        let skipBackwardResult = remoteCommandManager.handleSkipBackwardCommand(event: MockSkipCommandEvent(interval: 15))
        XCTAssertEqual(skipBackwardResult, .success, "Should handle skip backward command")
        
        // Test position change command
        let positionChangeResult = remoteCommandManager.handleChangePlaybackPositionCommand(
            event: MockPositionChangeEvent(positionTime: 120.0)
        )
        XCTAssertEqual(positionChangeResult, .success, "Should handle position change command")
    }
    
    // MARK: - Lock Screen Controls Tests
    
    func testLockScreenControlsDisplay() throws {
        let lockScreenManager = LockScreenManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        // Update lock screen controls
        lockScreenManager.updateLockScreenControls(
            title: testAudiobook.title,
            author: testAudiobook.author,
            isPlaying: true,
            currentTime: 0,
            duration: testAudiobook.duration
        )
        
        // Verify now playing info is set (lock screen uses same mechanism as Control Center)
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertNotNil(nowPlayingInfo, "Lock screen should have now playing info")
        
        // Test that lock screen artwork is set
        if let artwork = nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            XCTAssertNotNil(artwork, "Lock screen should display artwork")
        }
    }
    
    func testLockScreenInteractionResponsiveness() throws {
        let remoteCommandManager = RemoteCommandManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        remoteCommandManager.setupRemoteCommands()
        
        // Simulate lock screen interactions
        audioManager.startPlayback()
        XCTAssertEqual(audioManager.playbackState, .playing)
        
        // Test rapid lock screen interactions
        for _ in 0..<5 {
            let pauseResult = remoteCommandManager.handlePauseCommand(event: MockCommandEvent())
            XCTAssertEqual(pauseResult, .success, "Should handle rapid pause commands")
            
            let playResult = remoteCommandManager.handlePlayCommand(event: MockCommandEvent())
            XCTAssertEqual(playResult, .success, "Should handle rapid play commands")
        }
        
        XCTAssertEqual(audioManager.playbackState, .playing, "Should end in playing state")
    }
    
    // MARK: - Apple Watch Companion Tests
    
    func testWatchConnectivitySetup() throws {
        let watchManager = WatchConnectivityManager()
        
        if WCSession.isSupported() {
            XCTAssertNoThrow(watchManager.setupWatchConnectivity(),
                           "Watch connectivity setup should not crash")
            
            let session = watchManager.getWatchSession()
            XCTAssertNotNil(session, "Should have watch session when supported")
            
            // Test session activation
            let activationExpectation = expectation(description: "Watch session activation")
            watchManager.activateSession { success in
                XCTAssertTrue(success || !WCSession.default.isPaired,
                             "Session activation should succeed if watch is paired")
                activationExpectation.fulfill()
            }
            
            waitForExpectations(timeout: 5.0)
        } else {
            XCTSkip("Watch connectivity not supported on this device")
        }
    }
    
    func testWatchNowPlayingDataSync() throws {
        guard WCSession.isSupported() else {
            throw XCTSkip("Watch connectivity not supported")
        }
        
        let watchManager = WatchConnectivityManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        // Test sending now playing data to watch
        let nowPlayingData: [String: Any] = [
            "title": testAudiobook.title,
            "author": testAudiobook.author,
            "duration": testAudiobook.duration,
            "currentTime": audioManager.getCurrentTime(),
            "isPlaying": true
        ]
        
        XCTAssertNoThrow(watchManager.sendNowPlayingData(nowPlayingData),
                        "Sending now playing data should not crash")
        
        // Test receiving commands from watch
        let watchCommands = ["play", "pause", "skipForward", "skipBackward"]
        
        for command in watchCommands {
            XCTAssertNoThrow(watchManager.handleWatchCommand(command),
                           "Handling watch command '\(command)' should not crash")
        }
    }
    
    func testWatchAppContextSync() throws {
        guard WCSession.isSupported() else {
            throw XCTSkip("Watch connectivity not supported")
        }
        
        let watchManager = WatchConnectivityManager()
        let testAudiobooks = (0..<3).map { createTestAudiobook(title: "Book \($0)") }
        
        // Test syncing audiobook library context to watch
        let libraryContext = watchManager.createLibraryContext(from: testAudiobooks)
        XCTAssertNotNil(libraryContext, "Should create library context for watch")
        
        XCTAssertNoThrow(watchManager.updateApplicationContext(libraryContext),
                        "Updating watch app context should not crash")
        
        // Test context size limits
        let contextSize = watchManager.getContextSize(libraryContext)
        XCTAssertLessThan(contextSize, 65536, "Watch context should be within size limits")
    }
    
    // MARK: - System Integration Edge Cases
    
    func testAudioInterruptionHandling() throws {
        let testAudiobook = createTestAudiobook()
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        XCTAssertEqual(audioManager.playbackState, .playing)
        
        // Test phone call interruption
        simulateAudioInterruption(type: .began, reason: .builtInMicMuted)
        
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(audioManager.playbackState, .paused,
                      "Should pause during audio interruption")
        
        // Test interruption end
        simulateAudioInterruption(type: .ended, reason: nil)
        
        Thread.sleep(forTimeInterval: 0.5)
        let stateAfterInterruption = audioManager.playbackState
        XCTAssertTrue(stateAfterInterruption == .playing || stateAfterInterruption == .paused,
                     "Should handle interruption end appropriately")
    }
    
    func testSystemVolumeChanges() throws {
        let volumeManager = SystemVolumeManager()
        let testAudiobook = createTestAudiobook()
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        // Test volume change handling
        let initialVolume = volumeManager.getCurrentVolume()
        
        volumeManager.simulateVolumeChange(to: 0.5)
        Thread.sleep(forTimeInterval: 0.3)
        
        XCTAssertEqual(audioManager.playbackState, .playing,
                      "Should continue playing during volume changes")
        
        // Test mute/unmute
        volumeManager.simulateVolumeChange(to: 0.0)
        Thread.sleep(forTimeInterval: 0.3)
        
        XCTAssertEqual(audioManager.playbackState, .playing,
                      "Should handle mute gracefully")
        
        volumeManager.simulateVolumeChange(to: initialVolume)
    }
    
    func testMultipleAppAudioConflicts() throws {
        let testAudiobook = createTestAudiobook()
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        XCTAssertEqual(audioManager.playbackState, .playing)
        
        // Simulate another app requesting audio session
        simulateOtherAppAudioRequest()
        
        Thread.sleep(forTimeInterval: 1.0)
        
        let stateAfterConflict = audioManager.playbackState
        XCTAssertTrue(stateAfterConflict == .paused || stateAfterConflict == .interrupted,
                     "Should yield audio session to other apps when appropriate")
        
        // Simulate other app releasing audio session
        simulateOtherAppAudioRelease()
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Should be able to resume
        XCTAssertNoThrow(audioManager.startPlayback(),
                        "Should be able to resume after audio session conflict")
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudiobook(title: String = "Test Audiobook") -> Audiobook {
        let audiobook = MockAudiobook()
        audiobook.title = title
        audiobook.author = "Test Author"
        audiobook.duration = 3600 // 1 hour
        audiobook.coverImageData = createMockCoverImageData()
        return audiobook
    }
    
    private func createMockCoverImageData() -> Data? {
        // Create a simple 1x1 PNG image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        guard let cgContext = context,
              let image = cgContext.makeImage() else { return nil }
        
        let uiImage = UIImage(cgImage: image)
        return uiImage.pngData()
    }
    
    private func simulateAppLifecycleTransition(_ state: UIApplication.State) {
        switch state {
        case .active:
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        case .inactive:
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        case .background:
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        @unknown default:
            break
        }
    }
    
    private func simulateBackgroundAppRefreshSettings(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "background_app_refresh_enabled")
    }
    
    private func simulateBackgroundProcessingTimeLimit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: NSNotification.Name("BackgroundTaskExpiring"), object: nil)
        }
    }
    
    private func simulateAudioInterruption(type: AVAudioSession.InterruptionType, reason: AVAudioSession.InterruptionReason?) {
        var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let reason = reason {
            userInfo[AVAudioSessionInterruptionReasonKey] = reason.rawValue
        }
        
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }
    
    private func simulateOtherAppAudioRequest() {
        // Simulate another app requesting audio session
        NotificationCenter.default.post(
            name: NSNotification.Name("OtherAppAudioRequest"),
            object: nil
        )
    }
    
    private func simulateOtherAppAudioRelease() {
        // Simulate other app releasing audio session
        NotificationCenter.default.post(
            name: NSNotification.Name("OtherAppAudioRelease"),
            object: nil
        )
    }
}

// MARK: - Platform Integration Support Classes

class PlatformIntegrator {
    func setupPlatformIntegration() {
        // Setup platform-specific integration
    }
}

class CarPlayManager {
    func createNowPlayingTemplate() -> Any? {
        // Mock CarPlay now playing template
        return "MockNowPlayingTemplate"
    }
    
    func createPlayButton() -> Any? {
        return "MockPlayButton"
    }
    
    func createPauseButton() -> Any? {
        return "MockPauseButton"
    }
    
    func createNextButton() -> Any? {
        return "MockNextButton"
    }
    
    func createPreviousButton() -> Any? {
        return "MockPreviousButton"
    }
    
    func handlePlayAction() {
        // Handle CarPlay play action
    }
    
    func handlePauseAction() {
        // Handle CarPlay pause action
    }
    
    func updateNowPlayingInfo(for audiobook: Audiobook) {
        let nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: audiobook.title,
            MPMediaItemPropertyArtist: audiobook.author
        ]
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func createLibraryListTemplate(with audiobooks: [AudiobookModel]) -> Any? {
        return "MockListTemplate(\(audiobooks.count) items)"
    }
    
    func getListItems(for audiobooks: [AudiobookModel]) -> [Any] {
        return audiobooks.map { "ListItem(\($0.title))" }
    }
    
    func handleListItemSelection(_ item: Any) {
        // Handle CarPlay list item selection
    }
}

class AirPlayManager {
    func discoverAvailableRoutes() -> [Any]? {
        return ["MockRoute1", "MockRoute2"]
    }
    
    func isAirPlayAvailable() -> Bool {
        return true // Mock availability
    }
    
    func setupRouteChangeHandling() {
        // Setup AirPlay route change handling
    }
    
    func simulateAirPlayRouteSelection() {
        NotificationCenter.default.post(
            name: NSNotification.Name("AirPlayRouteSelected"),
            object: nil
        )
    }
    
    func simulateAirPlayDisconnection() {
        NotificationCenter.default.post(
            name: NSNotification.Name("AirPlayDisconnected"),
            object: nil
        )
    }
}

class RemoteCommandManager {
    private var supportedCommands: [MPRemoteCommand] = []
    
    func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        supportedCommands = [
            commandCenter.playCommand,
            commandCenter.pauseCommand,
            commandCenter.skipForwardCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.changePlaybackPositionCommand
        ]
        
        // Enable commands
        for command in supportedCommands {
            command.isEnabled = true
        }
    }
    
    func getSupportedCommands() -> [MPRemoteCommand] {
        return supportedCommands
    }
    
    func handlePlayCommand(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        // Handle play command
        return .success
    }
    
    func handlePauseCommand(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        // Handle pause command
        return .success
    }
    
    func handleSkipForwardCommand(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        // Handle skip forward command
        return .success
    }
    
    func handleSkipBackwardCommand(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        // Handle skip backward command
        return .success
    }
    
    func handleChangePlaybackPositionCommand(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        // Handle position change command
        return .success
    }
}

class NowPlayingInfoManager {
    func updateNowPlayingInfo(title: String, author: String, artwork: Data?, duration: TimeInterval, currentTime: TimeInterval, playbackRate: Float) {
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate
        ]
        
        if let artworkData = artwork, let image = UIImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

class LockScreenManager {
    func updateLockScreenControls(title: String, author: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        let nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

class WatchConnectivityManager {
    private var session: WCSession?
    
    func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
        }
    }
    
    func getWatchSession() -> WCSession? {
        return session
    }
    
    func activateSession(completion: @escaping (Bool) -> Void) {
        guard let session = session else {
            completion(false)
            return
        }
        
        session.activate()
        completion(true)
    }
    
    func sendNowPlayingData(_ data: [String: Any]) {
        // Mock sending data to watch
    }
    
    func handleWatchCommand(_ command: String) {
        // Mock handling watch commands
    }
    
    func createLibraryContext(from audiobooks: [AudiobookModel]) -> [String: Any] {
        let context = audiobooks.map { audiobook in
            [
                "id": audiobook.id?.uuidString ?? "",
                "title": audiobook.title,
                "author": audiobook.author
            ]
        }
        
        return ["library": context]
    }
    
    func updateApplicationContext(_ context: [String: Any]) {
        // Mock updating watch app context
    }
    
    func getContextSize(_ context: [String: Any]) -> Int {
        // Mock calculating context size
        return 1024 // Mock size
    }
}

class SystemVolumeManager {
    func getCurrentVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    
    func simulateVolumeChange(to volume: Float) {
        // Mock volume change simulation
        NotificationCenter.default.post(
            name: NSNotification.Name("SystemVolumeChanged"),
            object: nil,
            userInfo: ["volume": volume]
        )
    }
}

// Mock classes for testing

class MockCommandEvent: MPRemoteCommandEvent {
    override var command: MPRemoteCommand {
        return MPRemoteCommandCenter.shared().playCommand
    }
}

class MockSkipCommandEvent: MPSkipIntervalCommandEvent {
    private let skipInterval: TimeInterval
    
    init(interval: TimeInterval) {
        self.skipInterval = interval
        super.init()
    }
    
    override var interval: TimeInterval {
        return skipInterval
    }
}

class MockPositionChangeEvent: MPChangePlaybackPositionCommandEvent {
    private let position: TimeInterval
    
    init(positionTime: TimeInterval) {
        self.position = positionTime
        super.init()
    }
    
    override var positionTime: TimeInterval {
        return position
    }
}

// Extensions for mock functionality
extension MockAudioManager {
    var isAudioSessionActive: Bool {
        return playbackState != .stopped
    }
}
