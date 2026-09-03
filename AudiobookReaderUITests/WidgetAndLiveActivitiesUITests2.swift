//
//  WidgetAndLiveActivitiesUITests2.swift
//  AudiobookReaderUITests
//
//  Split from WidgetAndLiveActivitiesUITests.swift
//

import XCTest

final class WidgetAndLiveActivitiesUITests2: WidgetAndLiveActivitiesUITestCase {

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
}
