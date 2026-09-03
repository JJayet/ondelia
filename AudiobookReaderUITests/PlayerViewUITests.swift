//
//  PlayerViewUITests.swift
//  AudiobookReaderUITests
//
//  Created for Phase 3 Advanced UI Testing
//

import XCTest

/// Shared launch, teardown and player navigation for the PlayerViewUITests* classes.
@MainActor
class PlayerViewUITestCase: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchArguments.append("--reset-state")
        app.launch()
        
        // Wait for app to stabilize
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        let exists = libraryTab.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "App should launch successfully")
    }
    
    override func tearDown() async throws {
        app.terminate()
        app = nil
    }

    func navigateToPlayer() throws {
        // Navigate to library
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        if libraryTab.exists {
            libraryTab.tap()
        }
        
        // Wait for library to load
        sleep(1)
        
        // Find and tap the first audiobook (assuming test data exists)
        let firstAudiobook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
        
        if !firstAudiobook.exists {
            // If no audiobook exists, we need to import one first
            // For UI tests, we should ensure test data is available
            throw XCTSkip("No audiobooks available for testing - test data should be pre-loaded")
        }
        
        firstAudiobook.tap()
        
        // Wait for player to appear
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        let playerLoaded = playPauseButton.waitForExistence(timeout: 5)
        XCTAssertTrue(playerLoaded, "Player should load after tapping audiobook")
    }
}

final class PlayerViewUITests: PlayerViewUITestCase {

    // MARK: - Player Interface Interaction Tests
    
    func testPlayerBasicControls() throws {
        try navigateToPlayer()
        
        // Test play/pause functionality
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(playPauseButton.exists, "Play/pause button should exist")
        
        // Initially should be playing (auto-play feature)
        XCTAssertEqual(playPauseButton.label, "Pause", "Should be playing initially")
        
        // Tap to pause
        playPauseButton.tap()
        XCTAssertEqual(playPauseButton.label, "Play", "Should be paused after tap")
        
        // Tap to play again
        playPauseButton.tap()
        XCTAssertEqual(playPauseButton.label, "Pause", "Should be playing after second tap")
    }
    
    func testPlayerSkipControls() throws {
        try navigateToPlayer()
        
        let skipBackwardButton = app.buttons[AccessibilityIdentifiers.Player.skipBackwardButton]
        let skipForwardButton = app.buttons[AccessibilityIdentifiers.Player.skipForwardButton]
        
        XCTAssertTrue(skipBackwardButton.exists, "Skip backward button should exist")
        XCTAssertTrue(skipForwardButton.exists, "Skip forward button should exist")
        
        // Test skip functionality (buttons should be tappable)
        XCTAssertTrue(skipBackwardButton.isEnabled, "Skip backward should be enabled")
        XCTAssertTrue(skipForwardButton.isEnabled, "Skip forward should be enabled")
        
        skipBackwardButton.tap()
        skipForwardButton.tap()
        
        // Verify buttons still work after interaction
        XCTAssertTrue(skipBackwardButton.isEnabled, "Skip backward should remain enabled")
        XCTAssertTrue(skipForwardButton.isEnabled, "Skip forward should remain enabled")
    }
    
    func testPlayerProgressSliderInteraction() throws {
        try navigateToPlayer()
        
        let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
        XCTAssertTrue(progressSlider.exists, "Progress slider should exist")
        
        // Get initial value
        let initialValue = progressSlider.normalizedSliderPosition
        
        // Adjust slider forward
        progressSlider.adjust(toNormalizedSliderPosition: 0.3)
        
        // Allow time for seek operation
        sleep(1)
        
        // Verify slider moved (allowing for small differences due to seek precision)
        let newValue = progressSlider.normalizedSliderPosition
        XCTAssertNotEqual(initialValue, newValue, accuracy: 0.01, "Slider value should change after adjustment")
    }
    
    func testPlayerSpeedControl() throws {
        try navigateToPlayer()
        
        let speedControl = app.buttons[AccessibilityIdentifiers.Player.speedControl]
        XCTAssertTrue(speedControl.exists, "Speed control should exist")
        
        // Initially should be 1.0x
        XCTAssertTrue(speedControl.label.contains("1.0"), "Initial speed should be 1.0x")
        
        // Tap to change speed
        speedControl.tap()
        
        // Should cycle through speeds (1.0 -> 1.25 -> 1.5 -> 2.0 -> 0.75 -> 1.0)
        XCTAssertTrue(speedControl.label.contains("1.25") || 
                     speedControl.label.contains("1.5") ||
                     speedControl.label.contains("2.0") ||
                     speedControl.label.contains("0.75"),
                     "Speed should change after tap")
    }
    
    // MARK: - Mini-Player Functionality Tests
    
    func testMiniPlayerExpandCollapse() throws {
        try navigateToPlayer()
        
        // Swipe down to minimize
        app.swipeDown()
        
        // Should show mini player
        let miniPlayerContainer = app.otherElements[AccessibilityIdentifiers.MiniPlayer.container]
        XCTAssertTrue(miniPlayerContainer.waitForExistence(timeout: 2), "Mini player should appear")
        
        let miniPlayPause = app.buttons[AccessibilityIdentifiers.MiniPlayer.playPauseButton]
        XCTAssertTrue(miniPlayPause.exists, "Mini player play/pause should exist")
        
        // Tap mini player to expand
        miniPlayerContainer.tap()
        
        // Should return to full player
        let fullPlayerButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(fullPlayerButton.waitForExistence(timeout: 2), "Should return to full player")
    }
    
    func testMiniPlayerControls() throws {
        try navigateToPlayer()
        
        // Minimize to mini player
        app.swipeDown()
        
        let miniPlayerContainer = app.otherElements[AccessibilityIdentifiers.MiniPlayer.container]
        XCTAssertTrue(miniPlayerContainer.waitForExistence(timeout: 2), "Mini player should appear")
        
        // Test mini player controls
        let miniPlayPause = app.buttons[AccessibilityIdentifiers.MiniPlayer.playPauseButton]
        XCTAssertTrue(miniPlayPause.exists, "Mini player play/pause should exist")
        
        // Test play/pause in mini player
        miniPlayPause.tap()
        
        // Verify state change (button should still exist and be tappable)
        XCTAssertTrue(miniPlayPause.exists, "Mini player button should remain after tap")
        
        // Test progress bar exists
        let miniProgressBar = app.progressIndicators[AccessibilityIdentifiers.MiniPlayer.progressBar]
        XCTAssertTrue(miniProgressBar.exists, "Mini player progress bar should exist")
    }
    
    // MARK: - iOS 26 Liquid Glass Effects Validation
    
    func testLiquidGlassEffectsPresence() throws {
        try navigateToPlayer()
        
        // Verify glass effect containers exist
        // Note: XCUITest can't directly test visual effects, but we can test that
        // the containers and elements that should have glass effects are present
        
        let playerView = app.otherElements.containing(.button, identifier: AccessibilityIdentifiers.Player.playPauseButton).firstMatch
        XCTAssertTrue(playerView.exists, "Main player view should exist")
        
        // Test that interactive elements are present and functional
        let interactiveButtons = [
            AccessibilityIdentifiers.Player.playPauseButton,
            AccessibilityIdentifiers.Player.skipBackwardButton,
            AccessibilityIdentifiers.Player.skipForwardButton,
            AccessibilityIdentifiers.Player.chaptersButton,
            AccessibilityIdentifiers.Player.bookmarksButton
        ]
        
        for identifier in interactiveButtons {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "Button \(identifier) should exist")
            XCTAssertTrue(button.isEnabled, "Button \(identifier) should be enabled")
        }
    }
    
    func testGlassEffectInteractivity() throws {
        try navigateToPlayer()
        
        // Test that glass effect elements respond to touch
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        
        // Perform a press and hold to test interactive state
        playPauseButton.press(forDuration: 0.5)
        
        // Button should still be functional after interaction
        XCTAssertTrue(playPauseButton.exists, "Button should exist after press interaction")
        XCTAssertTrue(playPauseButton.isEnabled, "Button should remain enabled after press")
    }
}
