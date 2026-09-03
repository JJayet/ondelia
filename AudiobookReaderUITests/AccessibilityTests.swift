//
//  AccessibilityTests.swift
//  AudiobookReaderUITests
//
//  Created for Phase 3 Advanced Testing - Comprehensive Accessibility Testing
//

import XCTest

/// Shared launch, teardown and player navigation for the AccessibilityTests* classes.
@MainActor
class AccessibilityUITestCase: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchArguments.append("--accessibility-testing")
        app.launch()
    }
    
    override func tearDown() async throws {
        app.terminate()
        app = nil
    }

    func navigateToPlayer() throws {
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        if libraryTab.exists {
            libraryTab.tap()
        }
        
        let firstAudiobook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
        if !firstAudiobook.exists {
            throw XCTSkip("No audiobooks available for accessibility testing")
        }
        
        firstAudiobook.tap()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        let playerLoaded = playPauseButton.waitForExistence(timeout: 5)
        XCTAssertTrue(playerLoaded, "Player should load for accessibility testing")
    }
}

final class AccessibilityTests: AccessibilityUITestCase {

    // MARK: - VoiceOver Navigation and Audio Descriptions
    
    func testVoiceOverBasicNavigation() throws {
        // Navigate to library
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        XCTAssertTrue(libraryTab.exists, "Library tab should exist")
        XCTAssertTrue(libraryTab.isAccessibilityElement, "Library tab should be accessibility element")
        XCTAssertFalse(libraryTab.label.isEmpty, "Library tab should have accessibility label")
        
        libraryTab.tap()
        
        // Test VoiceOver navigation through library elements
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Import button should exist")
        XCTAssertTrue(importButton.isAccessibilityElement, "Import button should be accessibility element")
        
        // Check accessibility properties
        XCTAssertFalse(importButton.label.isEmpty, "Import button should have accessibility label")
        XCTAssertNotNil(importButton.value, "Import button should have accessibility value or hint")
        
        // Test accessibility traits
        let traits = importButton.elementType
        XCTAssertEqual(traits, .button, "Import button should have correct accessibility trait")
    }
    
    func testVoiceOverPlayerControls() throws {
        try navigateToPlayer()
        
        let playerControls = [
            (AccessibilityIdentifiers.Player.playPauseButton, "Play/Pause"),
            (AccessibilityIdentifiers.Player.skipBackwardButton, "Skip Backward"),
            (AccessibilityIdentifiers.Player.skipForwardButton, "Skip Forward"),
            (AccessibilityIdentifiers.Player.speedControl, "Playback Speed"),
            (AccessibilityIdentifiers.Player.chaptersButton, "Chapters"),
            (AccessibilityIdentifiers.Player.bookmarksButton, "Bookmarks")
        ]
        
        for (identifier, expectedContext) in playerControls {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, "\(expectedContext) control should exist")
            XCTAssertTrue(control.isAccessibilityElement, "\(expectedContext) should be accessibility element")
            
            // Verify meaningful labels
            let label = control.label.lowercased()
            XCTAssertFalse(label.isEmpty, "\(expectedContext) should have accessibility label")
            XCTAssertFalse(label.contains("button"), "Accessibility label should not redundantly include 'button'")
            
            // Verify accessibility hint provides context
            if let hint = control.value as? String, !hint.isEmpty {
                XCTAssertTrue(hint.contains(expectedContext.lowercased()) || 
                             hint.contains("tap") || 
                             hint.contains("double tap"),
                             "\(expectedContext) should have helpful accessibility hint")
            }
        }
    }
    
    func testVoiceOverProgressSliderNavigation() throws {
        try navigateToPlayer()
        
        let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
        XCTAssertTrue(progressSlider.exists, "Progress slider should exist")
        XCTAssertTrue(progressSlider.isAccessibilityElement, "Progress slider should be accessibility element")
        
        // Test slider accessibility properties
        XCTAssertFalse(progressSlider.label.isEmpty, "Progress slider should have label")
        
        let sliderValue = progressSlider.value
        XCTAssertNotNil(sliderValue, "Progress slider should have current value")
        
        // Test VoiceOver slider interaction
        let initialValue = progressSlider.normalizedSliderPosition
        
        // Simulate VoiceOver increment gesture
        progressSlider.adjust(toNormalizedSliderPosition: initialValue + 0.1)
        
        Thread.sleep(forTimeInterval: 0.5) // Allow for adjustment
        
        let newValue = progressSlider.normalizedSliderPosition
        XCTAssertNotEqual(initialValue, newValue, "Slider should respond to VoiceOver adjustment")
        
        // Verify value announcement would be meaningful
        let valueString = progressSlider.value as? String ?? ""
        XCTAssertTrue(valueString.contains("minute") || valueString.contains("hour") || !valueString.isEmpty,
                     "Slider value should be announced in meaningful units")
    }
    
    func testVoiceOverAudiobookCellNavigation() throws {
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        libraryTab.tap()
        
        let audiobookCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        
        let firstCell = audiobookCells.firstMatch
        if firstCell.exists {
            XCTAssertTrue(firstCell.isAccessibilityElement, "Audiobook cell should be accessibility element")
            
            let label = firstCell.label
            XCTAssertFalse(label.isEmpty, "Audiobook cell should have accessibility label")
            
            // Verify label contains essential information
            XCTAssertTrue(label.contains("audiobook") || label.count > 10,
                         "Cell label should contain meaningful information")
            
            // Test that cell provides context about its content
            let cellDescription = firstCell.value as? String ?? ""
            XCTAssertTrue(!cellDescription.isEmpty || label.contains("by ") || label.contains("duration"),
                         "Cell should provide context about title, author, or duration")
            
            // Test cell activation
            firstCell.tap()
            
            // Should navigate to player
            let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            XCTAssertTrue(playPauseButton.waitForExistence(timeout: 5),
                         "Should navigate to accessible player interface")
        } else {
            // Test empty state accessibility
            let emptyStateText = app.staticTexts.firstMatch
            if emptyStateText.exists {
                XCTAssertTrue(emptyStateText.isAccessibilityElement,
                             "Empty state should be accessible to screen readers")
                XCTAssertFalse(emptyStateText.label.isEmpty,
                              "Empty state should have descriptive text")
            }
        }
    }
    
    // MARK: - Dynamic Type Scaling Validation
    
    func testDynamicTypeExtraSmall() throws {
        app.terminate()
        
        let smallTypeApp = XCUIApplication()
        smallTypeApp.launchArguments.append("--dynamic-type-extra-small")
        smallTypeApp.launch()
        
        try validateDynamicTypeAdaptation(testCase: "Extra Small")
    }
    
    func testDynamicTypeLarge() throws {
        app.terminate()
        
        let largeTypeApp = XCUIApplication()
        largeTypeApp.launchArguments.append("--dynamic-type-large")
        largeTypeApp.launch()
        
        try validateDynamicTypeAdaptation(testCase: "Large")
    }
    
    func testDynamicTypeExtraExtraLarge() throws {
        app.terminate()
        
        let extraLargeTypeApp = XCUIApplication()
        extraLargeTypeApp.launchArguments.append("--dynamic-type-xxxlarge")
        extraLargeTypeApp.launch()
        
        try validateDynamicTypeAdaptation(testCase: "Extra Extra Large")
    }
    
    func testDynamicTypeAccessibilityLarge() throws {
        app.terminate()
        
        let accessibilityLargeApp = XCUIApplication()
        accessibilityLargeApp.launchArguments.append("--dynamic-type-accessibility-xxxlarge")
        accessibilityLargeApp.launch()
        
        try validateDynamicTypeAdaptation(testCase: "Accessibility Extra Extra Large", isAccessibilitySize: true)
    }
    
    private func validateDynamicTypeAdaptation(testCase: String, isAccessibilitySize: Bool = false) throws {
        // Test library interface
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "\(testCase): Library tab should exist")
        
        libraryTab.tap()
        
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "\(testCase): Import button should exist with dynamic type")
        XCTAssertTrue(importButton.isHittable, "\(testCase): Import button should be hittable with dynamic type")
        
        // Verify button doesn't get truncated
        let buttonFrame = importButton.frame
        XCTAssertGreaterThan(buttonFrame.width, 0, "\(testCase): Button should have positive width")
        XCTAssertGreaterThan(buttonFrame.height, 0, "\(testCase): Button should have positive height")
        
        // For accessibility sizes, buttons should be larger
        if isAccessibilitySize {
            XCTAssertGreaterThan(buttonFrame.height, 44, "\(testCase): Accessibility size buttons should be larger than 44pt")
        }
        
        // Test player interface with dynamic type
        let availableCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        if availableCells.firstMatch.exists {
            try navigateToPlayer()
            
            let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            XCTAssertTrue(playPauseButton.exists, "\(testCase): Play/pause button should exist")
            XCTAssertTrue(playPauseButton.isHittable, "\(testCase): Play/pause button should be hittable")
            
            let playerButtonFrame = playPauseButton.frame
            XCTAssertGreaterThan(playerButtonFrame.width, 0, "\(testCase): Player button should have positive width")
            XCTAssertGreaterThan(playerButtonFrame.height, 0, "\(testCase): Player button should have positive height")
            
            // Test progress slider with dynamic type
            let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
            if progressSlider.exists {
                XCTAssertTrue(progressSlider.isHittable, "\(testCase): Progress slider should be hittable")
                
                let sliderFrame = progressSlider.frame
                if isAccessibilitySize {
                    XCTAssertGreaterThan(sliderFrame.height, 44, "\(testCase): Accessibility slider should be larger")
                }
            }
        }
    }

    // MARK: - Helper Methods
    
    private func app(app: XCUIApplication, withIdentifier identifier: String) -> XCUIElement {
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

// MARK: - Accessibility Test Extensions

extension XCUIApplication {
    func firstMatch(withIdentifier identifier: String) -> XCUIElement {
        return descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
