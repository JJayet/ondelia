//
//  PlayerViewUITests.swift
//  IsoraUITests
//
//  Created for Phase 3 Advanced UI Testing
//

import XCTest

/// `--reset-state` so each player test starts from the seeded library alone.
@MainActor
class PlayerViewUITestCase: AudiobookUITestCase {
    override var extraLaunchArguments: [String] { ["--reset-state"] }
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

        let initialValue = progressSlider.value as? String
        XCTAssertNotNil(initialValue, "Progress slider should report a position")

        // Driven by coordinate rather than `adjust(toNormalizedSliderPosition:)`: the bar is a
        // custom control behind an accessibility representation, and a tap on it is the seek a
        // finger actually performs.
        progressSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()

        sleep(1)

        XCTAssertNotEqual(initialValue, progressSlider.value as? String, "Seeking should move the reported position")
    }
    
    func testPlayerSpeedControl() throws {
        try navigateToPlayer()
        
        let speedControl = app.buttons[AccessibilityIdentifiers.Player.speedControl]
        XCTAssertTrue(speedControl.exists, "Speed control should exist")
        
        // The chip's text reaches VoiceOver as the control's value, the label naming the control.
        XCTAssertEqual(speedControl.value as? String, "1x", "Initial speed should be 1x")
        
        // The control is a menu, not a cycling button: tapping opens it and a rate is picked.
        speedControl.tap()
        let fasterRate = app.buttons["1.5x"]
        XCTAssertTrue(fasterRate.waitForExistence(timeout: 2), "Speed menu should list the rates")
        fasterRate.tap()

        XCTAssertEqual(speedControl.value as? String, "1.5x", "Speed should follow the chosen rate")
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
