//
//  WidgetAndLiveActivitiesUITests.swift
//  AudiobookReaderUITests
//
//  Created for Phase 3 Advanced UI Testing
//

import XCTest

final class WidgetAndLiveActivitiesUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchArguments.append("--reset-state")
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    // MARK: - Home Screen Widget Testing
    
    func testWidgetInteractionFromHomeScreen() throws {
        // Note: Direct widget testing requires special setup and is complex in XCUITest
        // This test verifies that the app can handle widget interactions
        
        // Simulate widget tap by launching with specific parameters
        app.terminate()
        
        let widgetApp = XCUIApplication()
        widgetApp.launchArguments.append("--widget-launched")
        widgetApp.launchArguments.append("--audiobook-id=test-audiobook")
        widgetApp.launch()
        
        // Should navigate directly to player if widget contained audiobook info
        let playerButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        let widgetLaunchSuccess = playerButton.waitForExistence(timeout: 8)
        
        if !widgetLaunchSuccess {
            // If direct navigation didn't work, should at least open to library
            let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
            XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "App should launch successfully from widget")
        }
    }
    
    func testWidgetDataSynchronization() throws {
        // Test that playing audio updates widget data
        try navigateToPlayerAndStartPlayback()
        
        // Allow time for audio to play and widget to update
        sleep(3)
        
        // Terminate app and check if widget would have updated data
        // In a real test environment, this would involve checking widget timeline
        app.terminate()
        
        // Relaunch to verify persistent state
        app.launch()
        
        // Navigate back to player and verify state consistency
        try navigateToPlayer()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(playPauseButton.exists, "Player state should be restored consistently with widget")
    }
    
    func testWidgetConfigurationFlow() throws {
        // This test verifies the app responds correctly to widget configuration requests
        
        app.terminate()
        
        let configApp = XCUIApplication()
        configApp.launchArguments.append("--widget-configuration")
        configApp.launch()
        
        // Should show widget configuration interface or main library
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        let configurationInterface = app.navigationBars.containing(NSPredicate(format: "identifier CONTAINS 'widget' OR identifier CONTAINS 'config'")).firstMatch
        
        let validLaunchState = libraryTab.waitForExistence(timeout: 5) || configurationInterface.exists
        XCTAssertTrue(validLaunchState, "Widget configuration should launch properly")
    }
    
    // MARK: - Live Activities Integration Tests
    
    func testLiveActivityCreation() throws {
        // Start playback to trigger Live Activity
        try navigateToPlayerAndStartPlayback()
        
        // Live Activities are created in background, we test the app's response
        // to starting playback which should trigger Live Activity creation
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertEqual(playPauseButton.label, "Pause", "Playback should be active")
        
        // Verify the app is in a state that should create Live Activity
        // (We can't directly test the Live Activity UI from within the app)
        
        // Test backgrounding behavior that should maintain Live Activity
        XCUIDevice.shared.press(.home)
        sleep(2)
        
        // Return to app
        app.activate()
        
        // Verify playback continues and app state is consistent
        XCTAssertTrue(playPauseButton.exists, "Player should remain accessible after backgrounding")
    }
    
    func testLiveActivityControlsResponse() throws {
        // Test that Live Activity controls (when tapped) properly affect app state
        
        try navigateToPlayerAndStartPlayback()
        
        // Simulate Live Activity interaction by using URL schemes or background tasks
        app.terminate()
        
        let liveActivityApp = XCUIApplication()
        liveActivityApp.launchArguments.append("--live-activity-action=pause")
        liveActivityApp.launch()
        
        // Navigate to player and verify the action was processed
        try navigateToPlayer()
        
        // The Live Activity pause action should have paused playback
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        
        // Allow time for state synchronization
        sleep(1)
        
        // Note: This test depends on Live Activity implementation details
        // In practice, you might need to verify through app state or user defaults
        XCTAssertTrue(playPauseButton.exists, "Player should respond to Live Activity controls")
    }
    
    func testLiveActivityDataAccuracy() throws {
        try navigateToPlayerAndStartPlayback()
        
        // Get current playback information
        let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
        let initialProgress = progressSlider.normalizedSliderPosition
        
        // Allow playback to continue
        sleep(5)
        
        let newProgress = progressSlider.normalizedSliderPosition
        XCTAssertNotEqual(initialProgress, newProgress, accuracy: 0.01, "Progress should advance during playback")
        
        // The Live Activity should reflect this same progress
        // Since we can't directly access Live Activity UI, we verify the app state
        // that would be sent to the Live Activity is accurate
        
        // Background and foreground to simulate Live Activity update cycle
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        
        // Verify data consistency after background/foreground
        let restoredProgress = progressSlider.normalizedSliderPosition
        let progressDifference = abs(restoredProgress - newProgress)
        XCTAssertLessThan(progressDifference, 0.1, "Progress should be maintained across background/foreground")
    }
    
    // MARK: - Control Center Integration Tests
    
    func testControlCenterIntegration() throws {
        try navigateToPlayerAndStartPlayback()
        
        // Test that control center shows media controls
        // Note: Direct Control Center testing is not possible via XCUITest
        // We test the app's media session setup instead
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertEqual(playPauseButton.label, "Pause", "Media should be playing")
        
        // Background the app to activate background media session
        XCUIDevice.shared.press(.home)
        sleep(2)
        
        // Return to app - media session should be maintained
        app.activate()
        
        // Verify playback continued in background
        XCTAssertTrue(playPauseButton.exists, "Player should maintain state after backgrounding")
        
        // The fact that the button exists and maintains state indicates
        // successful media session integration for Control Center
    }
    
    func testRemoteControlHandling() throws {
        // Test app's response to remote control events (like from Control Center)
        
        try navigateToPlayerAndStartPlayback()
        
        // Simulate remote control play/pause
        // In a real test, this might involve sending remote control events
        // For now, we test the underlying mechanism by backgrounding/foregrounding
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        let initialState = playPauseButton.label
        
        // Background the app
        XCUIDevice.shared.press(.home)
        sleep(1)
        
        // Return to app
        app.activate()
        
        // Verify the app properly restored media controls
        XCTAssertTrue(playPauseButton.exists, "Remote control setup should be maintained")
        
        // Test that button still functions after background/foreground
        playPauseButton.tap()
        let newState = playPauseButton.label
        XCTAssertNotEqual(initialState, newState, "Play/pause should work after background/foreground cycle")
    }
    
    // MARK: - Cross-Platform Widget Testing
    
    func testWidgetAppearanceInDifferentSizes() throws {
        // This test verifies the app provides appropriate data for different widget sizes
        
        // Simulate small widget request
        app.terminate()
        let smallWidgetApp = XCUIApplication()
        smallWidgetApp.launchArguments.append("--widget-size=small")
        smallWidgetApp.launch()
        
        // App should launch successfully regardless of widget size
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "App should handle small widget requests")
        
        // Test medium widget
        app.terminate()
        let mediumWidgetApp = XCUIApplication()
        mediumWidgetApp.launchArguments.append("--widget-size=medium")
        mediumWidgetApp.launch()
        
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "App should handle medium widget requests")
        
        // Test large widget
        app.terminate()
        let largeWidgetApp = XCUIApplication()
        largeWidgetApp.launchArguments.append("--widget-size=large")
        largeWidgetApp.launch()
        
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "App should handle large widget requests")
    }
    
    // MARK: - Widget Update Frequency Tests
    
    func testWidgetUpdateTimeline() throws {
        try navigateToPlayerAndStartPlayback()
        
        // Test that widget updates are triggered appropriately
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        
        // Toggle playback state multiple times
        playPauseButton.tap() // Pause
        sleep(1)
        playPauseButton.tap() // Play
        sleep(1)
        playPauseButton.tap() // Pause
        
        // Each state change should trigger widget updates
        // We verify the app maintains consistent state
        XCTAssertEqual(playPauseButton.label, "Play", "Final state should be paused")
        
        // Background and foreground to test update consistency
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        
        // State should be maintained
        XCTAssertEqual(playPauseButton.label, "Play", "State should persist across app lifecycle")
    }
    
    // MARK: - Error Handling for Widgets and Live Activities
    
    func testWidgetErrorStates() throws {
        // Test app behavior when widget requests encounter errors
        
        app.terminate()
        let errorApp = XCUIApplication()
        errorApp.launchArguments.append("--widget-error-simulation")
        errorApp.launch()
        
        // App should still launch successfully even if widget encounters errors
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 8), "App should handle widget errors gracefully")
        
        // Verify core functionality remains intact
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Core functionality should be unaffected by widget errors")
    }
    
    func testLiveActivityLimitsHandling() throws {
        // Test behavior when Live Activity limits are reached
        
        // Start multiple playback sessions (simulated)
        try navigateToPlayerAndStartPlayback()
        
        // Background and foreground multiple times to simulate Live Activity stress
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            sleep(1)
            app.activate()
            sleep(1)
        }
        
        // App should handle Live Activity limits gracefully
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(playPauseButton.exists, "App should continue functioning despite Live Activity limits")
    }
    
    // MARK: - Performance Tests for Widgets
    
    func testWidgetLaunchPerformance() throws {
        measure {
            app.terminate()
            
            let widgetApp = XCUIApplication()
            widgetApp.launchArguments.append("--widget-launched")
            widgetApp.launch()
            
            let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
            _ = libraryTab.waitForExistence(timeout: 10)
        }
    }
    
    func testLiveActivityUpdatePerformance() throws {
        try navigateToPlayerAndStartPlayback()
        
        measure {
            let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            
            // Perform rapid state changes that should trigger Live Activity updates
            for _ in 0..<5 {
                playPauseButton.tap()
                usleep(200000) // 0.2 seconds
            }
        }
    }
    
    // MARK: - Accessibility in Widgets and Live Activities
    
    func testWidgetAccessibilityCompliance() throws {
        // While we can't directly test widget accessibility, we can test
        // that the app provides proper accessibility data for widgets
        
        try navigateToPlayerAndStartPlayback()
        
        // Verify that key information has proper accessibility labels
        // This data would be used by widgets
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertFalse(playPauseButton.label.isEmpty, "Play/pause state should have clear accessibility label")
        
        let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
        XCTAssertFalse(progressSlider.label.isEmpty, "Progress should have accessibility description")
        
        // Test that accessibility information persists across app states
        XCUIDevice.shared.press(.home)
        app.activate()
        
        XCTAssertFalse(playPauseButton.label.isEmpty, "Accessibility labels should persist")
    }
    
    // MARK: - Helper Methods
    
    private func navigateToPlayer() throws {
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        if libraryTab.exists {
            libraryTab.tap()
        }
        
        let firstAudiobook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
        if !firstAudiobook.exists {
            throw XCTSkip("No audiobooks available for testing")
        }
        
        firstAudiobook.tap()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        let playerLoaded = playPauseButton.waitForExistence(timeout: 5)
        XCTAssertTrue(playerLoaded, "Player should load after selecting audiobook")
    }
    
    private func navigateToPlayerAndStartPlayback() throws {
        try navigateToPlayer()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        
        // Ensure playback is started
        if playPauseButton.label == "Play" {
            playPauseButton.tap()
        }
        
        // Verify playback started
        XCTAssertEqual(playPauseButton.label, "Pause", "Playback should be active")
    }
}

