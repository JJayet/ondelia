//
//  AccessibilityTests.swift
//  AudiobookReaderUITests
//
//  Created for Phase 3 Advanced Testing - Comprehensive Accessibility Testing
//

import XCTest

/// Accessibility runs against whatever the library holds, seeded on first launch.
@MainActor
class AccessibilityUITestCase: AudiobookUITestCase {
    override var extraLaunchArguments: [String] { ["--accessibility-testing"] }
}

final class AccessibilityTests: AccessibilityUITestCase {

    // MARK: - VoiceOver Navigation and Audio Descriptions
    
    func testVoiceOverBasicNavigation() throws {
        // Navigate to library
        XCTAssertTrue(libraryTab.exists, "Library tab should exist")
        XCTAssertFalse(libraryTab.label.isEmpty, "Library tab should have accessibility label")
        
        libraryTab.tap()
        
        // Test VoiceOver navigation through library elements
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Import button should exist")
        
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
        
        // Test slider accessibility properties
        XCTAssertFalse(progressSlider.label.isEmpty, "Progress slider should have label")
        
        let sliderValue = progressSlider.value
        XCTAssertNotNil(sliderValue, "Progress slider should have current value")
        
        // Test VoiceOver slider interaction
        let initialValue = progressSlider.normalizedSliderPosition
        
        // A tenth of the way along lands under the thumb and no drag registers, so this drives
        // the same position, and waits as long, as the sibling interaction test.
        progressSlider.adjust(toNormalizedSliderPosition: 0.3)
        
        sleep(1) // Allow the seek to land
        
        let newValue = progressSlider.normalizedSliderPosition
        XCTAssertNotEqual(initialValue, newValue, "Slider should respond to VoiceOver adjustment")
        
        // Verify value announcement would be meaningful
        let valueString = progressSlider.value as? String ?? ""
        XCTAssertTrue(valueString.contains("minute") || valueString.contains("hour") || !valueString.isEmpty,
                     "Slider value should be announced in meaningful units")
    }
    
    func testVoiceOverAudiobookCellNavigation() throws {
        libraryTab.tap()
        
        let audiobookCells = audiobookRows
        
        let firstCell = audiobookCells.firstMatch
        if firstCell.exists {
            
            let label = firstCell.label
            XCTAssertFalse(label.isEmpty, "Audiobook cell should have accessibility label")
            
            // Verify label contains essential information
            XCTAssertTrue(label.contains("audiobook") || label.count > 10,
                         "Cell label should contain meaningful information")
            
            // The row reads as one phrase — title, author, state, position — so the context is
            // in those components rather than in a separate accessibility value.
            XCTAssertTrue(label.split(separator: ",").count >= 2,
                         "Cell should provide context beyond a bare title, got: \(label)")
            
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
                XCTAssertFalse(emptyStateText.label.isEmpty,
                              "Empty state should have descriptive text")
            }
        }
    }
    
    // MARK: - Dynamic Type Scaling Validation
    
    func testDynamicTypeExtraSmall() throws {
        relaunch(with: ["--dynamic-type-extra-small"])
        
        try validateDynamicTypeAdaptation(testCase: "Extra Small")
    }
    
    func testDynamicTypeLarge() throws {
        relaunch(with: ["--dynamic-type-large"])
        
        try validateDynamicTypeAdaptation(testCase: "Large")
    }
    
    func testDynamicTypeExtraExtraLarge() throws {
        relaunch(with: ["--dynamic-type-xxxlarge"])
        
        try validateDynamicTypeAdaptation(testCase: "Extra Extra Large")
    }
    
    func testDynamicTypeAccessibilityLarge() throws {
        relaunch(with: ["--dynamic-type-accessibility-xxxlarge"])
        
        try validateDynamicTypeAdaptation(testCase: "Accessibility Extra Extra Large", isAccessibilitySize: true)
    }
    
    private func validateDynamicTypeAdaptation(testCase: String, isAccessibilitySize: Bool = false) throws {
        // Test library interface
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5), "\(testCase): Library tab should exist")
        
        libraryTab.tap()
        
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "\(testCase): Import button should exist with dynamic type")
        XCTAssertTrue(importButton.isHittable, "\(testCase): Import button should be hittable with dynamic type")
        
        // Verify button doesn't get truncated
        let buttonFrame = importButton.frame
        XCTAssertGreaterThan(buttonFrame.width, 0, "\(testCase): Button should have positive width")
        XCTAssertGreaterThan(buttonFrame.height, 0, "\(testCase): Button should have positive height")
        
        // Toolbar glyphs keep their own metrics whatever the type size; the content does grow,
        // so a library row is what says the size was applied.
        if isAccessibilitySize {
            // Everything above the list is taller too, so the first row starts below the fold
            // and the lazy stack has not built it yet.
            let row = audiobookRows.firstMatch
            for _ in 0..<5 where !row.exists {
                app.swipeUp()
            }
            XCTAssertTrue(row.exists, "\(testCase): Library row should be reachable by scrolling")
            XCTAssertGreaterThan(row.frame.height, 127,
                                 "\(testCase): Rows should grow past their default height")
        }
        
        // Test player interface with dynamic type
        let availableCells = audiobookRows
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
                
                // A slider keeps its own control metrics at every type size — what matters is
                // that it is still reachable and still spans the width to drag along.
                XCTAssertGreaterThan(progressSlider.frame.width, 200,
                                     "\(testCase): Progress slider should stay wide enough to drag")
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
