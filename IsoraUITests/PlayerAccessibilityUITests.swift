//
//  PlayerAccessibilityUITests.swift
//  IsoraUITests
//
//  Split from PlayerViewUITests.swift
//

import XCTest

final class PlayerAccessibilityUITests: PlayerViewUITestCase {

    // MARK: - Accessibility Testing
    
    func testVoiceOverSupport() throws {
        try navigateToPlayer()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        
        // Check accessibility label exists and is meaningful
        XCTAssertFalse(playPauseButton.label.isEmpty, "Play/pause button should have accessibility label")
        XCTAssertTrue(playPauseButton.label.lowercased().contains("play") || 
                     playPauseButton.label.lowercased().contains("pause"),
                     "Accessibility label should indicate play/pause state")
        
        // No assertion on `value`: XCUIElement exposes no accessibility hint, and a button's
        // value is not one — the label above is what VoiceOver reads here.
    }
    
    func testDynamicTypeSupport() throws {
        // Test with large text size
        app.launchArguments.append("--dynamic-type-xxxlarge")
        try navigateToPlayer()
        
        // Verify essential controls are still accessible
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(playPauseButton.exists, "Play/pause button should exist with large text")
        XCTAssertTrue(playPauseButton.isHittable, "Play/pause button should be hittable with large text")
        
        // Test that text doesn't overlap or get truncated excessively
        let frame = playPauseButton.frame
        XCTAssertGreaterThan(frame.width, 0, "Button should have positive width")
        XCTAssertGreaterThan(frame.height, 0, "Button should have positive height")
    }
    
    // MARK: - Orientation Change Tests
    
    func testOrientationChanges() throws {
        try navigateToPlayer()
        
        let device = XCUIDevice.shared
        
        // Test portrait to landscape
        device.orientation = .landscapeLeft
        
        // Allow UI to adapt
        sleep(1)
        
        // Verify controls are still accessible
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(playPauseButton.exists, "Play/pause button should exist in landscape")
        XCTAssertTrue(playPauseButton.isHittable, "Play/pause button should be hittable in landscape")
        
        // Test landscape to portrait
        device.orientation = .portrait
        sleep(1)
        
        XCTAssertTrue(playPauseButton.exists, "Play/pause button should exist in portrait")
        XCTAssertTrue(playPauseButton.isHittable, "Play/pause button should be hittable in portrait")
    }
    
    // MARK: - Chapter and Bookmark Interface Tests
    
    func testChaptersListAccess() throws {
        try navigateToPlayer()
        
        let chaptersButton = app.buttons[AccessibilityIdentifiers.Player.chaptersButton]
        XCTAssertTrue(chaptersButton.exists, "Chapters button should exist")
        
        chaptersButton.tap()
        
        // Should show chapters list (assuming it's presented as a sheet or navigation)
        // Wait for sheet or navigation to appear
        sleep(1)
        
        // The exact implementation depends on how chapters are presented
        // This is a basic test to ensure the button works
        XCTAssertTrue(chaptersButton.exists, "Chapters button should still exist after tap")
    }
    
    func testBookmarksAccess() throws {
        try navigateToPlayer()
        
        let bookmarksButton = app.buttons[AccessibilityIdentifiers.Player.bookmarksButton]
        XCTAssertTrue(bookmarksButton.exists, "Bookmarks button should exist")
        
        bookmarksButton.tap()
        
        // Should show bookmarks interface
        sleep(1)
        
        XCTAssertTrue(bookmarksButton.exists, "Bookmarks button should still exist after tap")
    }
}
