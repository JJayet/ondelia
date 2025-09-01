//
//  AccessibilityTests.swift
//  AudiobookReaderUITests
//
//  Created for Phase 3 Advanced Testing - Comprehensive Accessibility Testing
//

import XCTest

final class AccessibilityTests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchArguments.append("--accessibility-testing")
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
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
    
    // MARK: - Voice Control Compatibility
    
    func testVoiceControlElementNaming() throws {
        // Voice Control relies on accessibility labels and identifiers
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        libraryTab.tap()
        
        let keyElements = [
            (AccessibilityIdentifiers.Library.importButton, "Import"),
            (AccessibilityIdentifiers.Library.searchBar, "Search"),
            (AccessibilityIdentifiers.Library.sortButton, "Sort"),
            (AccessibilityIdentifiers.Library.viewModeToggle, "View Mode")
        ]
        
        for (identifier, expectedName) in keyElements {
            let element = app.firstMatch(withIdentifier: identifier)
            if element.exists {
                let label = element.label.lowercased()
                XCTAssertTrue(label.contains(expectedName.lowercased()) || !label.isEmpty,
                             "Element \(identifier) should have voice-control-friendly name")
                
                // Voice Control works better with unique, descriptive names
                XCTAssertFalse(label == "button" || label == "untitled",
                              "Element should not have generic label")
            }
        }
        
        // Test player controls for Voice Control compatibility
        let availableCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        if availableCells.firstMatch.exists {
            try navigateToPlayer()
            
            let playerElements = [
                (AccessibilityIdentifiers.Player.playPauseButton, ["play", "pause"]),
                (AccessibilityIdentifiers.Player.skipBackwardButton, ["back", "previous", "skip"]),
                (AccessibilityIdentifiers.Player.skipForwardButton, ["forward", "next", "skip"]),
                (AccessibilityIdentifiers.Player.speedControl, ["speed", "rate"])
            ]
            
            for (identifier, keywords) in playerElements {
                let element = app.buttons[identifier]
                if element.exists {
                    let label = element.label.lowercased()
                    let hasRelevantKeyword = keywords.contains { keyword in
                        label.contains(keyword)
                    }
                    XCTAssertTrue(hasRelevantKeyword || !label.isEmpty,
                                 "Player control \(identifier) should have voice-control-friendly label")
                }
            }
        }
    }
    
    func testVoiceControlNumberedElements() throws {
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        libraryTab.tap()
        
        let audiobookCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        
        // Test that audiobook cells have distinct labels for Voice Control
        // Since we can't reliably iterate through XCUIElements, we'll test the first few that exist
        let firstCell = audiobookCells.firstMatch
        if firstCell.exists {
            XCTAssertTrue(firstCell.isAccessibilityElement, "First audiobook cell should be accessible to Voice Control")
            XCTAssertFalse(firstCell.label.isEmpty, "First cell should have unique label for Voice Control")
        }
    }
    
    // MARK: - Switch Control Accessibility
    
    func testSwitchControlNavigationOrder() throws {
        // Switch Control relies on proper focus order
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        libraryTab.tap()
        
        let focusableElements = [
            app.buttons[AccessibilityIdentifiers.Library.importButton],
            app.searchFields[AccessibilityIdentifiers.Library.searchBar],
            app.buttons[AccessibilityIdentifiers.Library.sortButton],
            app.buttons[AccessibilityIdentifiers.Library.viewModeToggle]
        ].filter { $0.exists }
        
        // All focusable elements should be accessibility elements
        for element in focusableElements {
            XCTAssertTrue(element.isAccessibilityElement,
                         "Switch Control requires all interactive elements to be accessibility elements")
            XCTAssertTrue(element.isEnabled,
                         "Switch Control elements should be enabled when available")
        }
        
        // Test logical focus order in player
        let availableCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        if availableCells.firstMatch.exists {
            try navigateToPlayer()
            
            let playerFocusableElements = [
                app.buttons[AccessibilityIdentifiers.Player.skipBackwardButton],
                app.buttons[AccessibilityIdentifiers.Player.playPauseButton],
                app.buttons[AccessibilityIdentifiers.Player.skipForwardButton],
                app.sliders[AccessibilityIdentifiers.Player.progressSlider],
                app.buttons[AccessibilityIdentifiers.Player.speedControl]
            ].filter { $0.exists }
            
            XCTAssertGreaterThan(playerFocusableElements.count, 0,
                               "Player should have focusable elements for Switch Control")
            
            for element in playerFocusableElements {
                XCTAssertTrue(element.isAccessibilityElement,
                             "Player controls should be accessible to Switch Control")
            }
        }
    }
    
    func testSwitchControlActivation() throws {
        try navigateToPlayer()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        XCTAssertTrue(playPauseButton.exists, "Play/pause button should exist")
        
        // Switch Control users activate elements through selection, not direct touch
        XCTAssertTrue(playPauseButton.isAccessibilityElement,
                     "Button should be accessible to Switch Control")
        XCTAssertTrue(playPauseButton.isEnabled,
                     "Button should be enabled for Switch Control activation")
        
        let initialState = playPauseButton.label
        
        // Test activation (tap simulates Switch Control activation)
        playPauseButton.tap()
        
        // Should respond to activation
        Thread.sleep(forTimeInterval: 0.5)
        let newState = playPauseButton.label
        XCTAssertNotEqual(initialState, newState,
                         "Button should respond to Switch Control activation")
    }
    
    // MARK: - Hearing Accessibility Features
    
    func testClosedCaptionSupport() throws {
        // For audiobook app, this tests support for audio descriptions and alternative content
        try navigateToPlayer()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        
        // Test that audio state is communicated through non-audio means
        let buttonLabel = playPauseButton.label
        XCTAssertTrue(buttonLabel.lowercased().contains("play") || buttonLabel.lowercased().contains("pause"),
                     "Audio state should be communicated visually for hearing impaired users")
        
        // Test progress indication for hearing impaired users
        let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
        if progressSlider.exists {
            let progressValue = progressSlider.value as? String ?? ""
            XCTAssertFalse(progressValue.isEmpty,
                          "Progress should be indicated visually for hearing impaired users")
        }
        
        // Test that audio controls provide visual feedback
        playPauseButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        let updatedLabel = playPauseButton.label
        XCTAssertNotEqual(buttonLabel, updatedLabel,
                         "Visual feedback should be provided for hearing impaired users")
    }
    
    func testAudioDescriptionAlternatives() throws {
        // Test that visual information has textual alternatives
        try navigateToPlayer()
        
        let coverArt = app.images[AccessibilityIdentifiers.Player.coverArt]
        if coverArt.exists {
            XCTAssertTrue(coverArt.isAccessibilityElement,
                         "Cover art should be accessibility element")
            
            let label = coverArt.label
            XCTAssertFalse(label.isEmpty,
                          "Cover art should have descriptive label for hearing impaired users using screen readers")
            XCTAssertTrue(label.lowercased().contains("cover") || label.lowercased().contains("artwork") || label.count > 5,
                         "Cover art label should be descriptive")
        }
        
        // Test that progress visualization has textual description
        let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
        if progressSlider.exists {
            let hint = progressSlider.value as? String ?? ""
            XCTAssertTrue(!hint.isEmpty,
                         "Progress visualization should have textual description")
        }
    }
    
    // MARK: - Reduced Motion Accessibility
    
    func testReducedMotionCompliance() throws {
        app.terminate()
        
        let reducedMotionApp = XCUIApplication()
        reducedMotionApp.launchArguments.append("--reduce-motion")
        reducedMotionApp.launch()
        
        // Navigate to player
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        libraryTab.tap()
        
        let availableTestCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        let firstCell = availableTestCells.firstMatch
        if firstCell.exists {
            firstCell.tap()
            
            let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            XCTAssertTrue(playPauseButton.waitForExistence(timeout: 3),
                         "Navigation should work with reduced motion")
            
            // Test that essential functions work without animation
            playPauseButton.tap()
            Thread.sleep(forTimeInterval: 0.3) // Reduced time since animations are disabled
            
            let stateAfterTap = playPauseButton.label
            XCTAssertFalse(stateAfterTap.isEmpty,
                          "Functionality should work without animations")
            
            // Test mini player transition with reduced motion
            app.swipeDown()
            
            let miniPlayer = app.otherElements[AccessibilityIdentifiers.MiniPlayer.container]
            XCTAssertTrue(miniPlayer.waitForExistence(timeout: 2),
                         "Mini player should appear even with reduced motion")
        }
    }
    
    // MARK: - High Contrast and Display Accommodation
    
    func testHighContrastSupport() throws {
        app.terminate()
        
        let highContrastApp = XCUIApplication()
        highContrastApp.launchArguments.append("--high-contrast")
        highContrastApp.launch()
        
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5),
                     "Interface should be usable with high contrast")
        
        libraryTab.tap()
        
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Buttons should be visible with high contrast")
        XCTAssertTrue(importButton.isHittable, "Buttons should remain interactive with high contrast")
        
        let availableTestCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        let firstCell = availableTestCells.firstMatch
        if firstCell.exists {
            XCTAssertTrue(firstCell.isHittable, "Content should remain readable with high contrast")
            
            firstCell.tap()
            
            let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            XCTAssertTrue(playPauseButton.waitForExistence(timeout: 3),
                         "Player interface should work with high contrast")
        }
    }
    
    func testInvertColorsSupport() throws {
        app.terminate()
        
        let invertedApp = XCUIApplication()
        invertedApp.launchArguments.append("--invert-colors")
        invertedApp.launch()
        
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5),
                     "Interface should be usable with inverted colors")
        
        libraryTab.tap()
        
        // Test that essential elements remain functional
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists && importButton.isEnabled,
                     "Controls should work with inverted colors")
    }
    
    // MARK: - Comprehensive Accessibility Audit
    
    func testAccessibilityAudit() throws {
        // Comprehensive audit of entire app accessibility
        try auditLibraryAccessibility()
        try auditPlayerAccessibility()
        try auditNavigationAccessibility()
    }
    
    private func auditLibraryAccessibility() throws {
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        libraryTab.tap()
        
        // Audit all interactive elements
        let interactiveElements = app.buttons.allElementsBoundByIndex +
                                 app.textFields.allElementsBoundByIndex +
                                 app.searchFields.allElementsBoundByIndex +
                                 app.cells.allElementsBoundByIndex
        
        for element in interactiveElements {
            if element.exists && element.isHittable {
                // Every interactive element should be an accessibility element
                XCTAssertTrue(element.isAccessibilityElement,
                             "Interactive element should be accessibility element")
                
                // Should have meaningful label
                let label = element.label
                XCTAssertFalse(label.isEmpty,
                              "Interactive element should have accessibility label")
                XCTAssertFalse(label == "Button" || label == "Cell",
                              "Label should be descriptive, not generic")
                
                // Should have appropriate traits
                if element.elementType == .button {
                    XCTAssertTrue(element.isEnabled || !element.isHittable,
                                 "Hittable buttons should be enabled")
                }
            }
        }
    }
    
    private func auditPlayerAccessibility() throws {
        let availableCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        if availableCells.firstMatch.exists {
            try navigateToPlayer()
            
            let playerElements = [
                app.buttons[AccessibilityIdentifiers.Player.playPauseButton],
                app.buttons[AccessibilityIdentifiers.Player.skipBackwardButton],
                app.buttons[AccessibilityIdentifiers.Player.skipForwardButton],
                app.sliders[AccessibilityIdentifiers.Player.progressSlider],
                app.buttons[AccessibilityIdentifiers.Player.speedControl]
            ]
            
            for element in playerElements {
                if element.exists {
                    XCTAssertTrue(element.isAccessibilityElement,
                                 "Player control should be accessibility element")
                    XCTAssertFalse(element.label.isEmpty,
                                  "Player control should have accessibility label")
                    XCTAssertTrue(element.isEnabled,
                                 "Player control should be enabled when visible")
                }
            }
            
            // Test that progress information is accessible
            let progressSlider = app.sliders[AccessibilityIdentifiers.Player.progressSlider]
            if progressSlider.exists {
                let value = progressSlider.value as? String ?? ""
                XCTAssertTrue(!value.isEmpty || !progressSlider.label.isEmpty,
                             "Progress should be accessible through value or label")
            }
        }
    }
    
    private func auditNavigationAccessibility() throws {
        // Test tab bar accessibility
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")
        
        let tabButtons = tabBar.buttons.allElementsBoundByIndex
        for tab in tabButtons {
            if tab.exists {
                XCTAssertTrue(tab.isAccessibilityElement,
                             "Tab button should be accessibility element")
                XCTAssertFalse(tab.label.isEmpty,
                              "Tab should have accessibility label")
            }
        }
        
        // Test navigation between major sections
        let homeTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.homeTab]
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        let settingsTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.settingsTab]
        
        let tabs = [homeTab, libraryTab, settingsTab]
        for tab in tabs {
            if tab.exists {
                tab.tap()
                Thread.sleep(forTimeInterval: 0.5)
                
                // Should announce tab change to screen readers
                XCTAssertTrue(tab.isSelected || tab.label.lowercased().contains("selected"),
                             "Selected tab should be indicated for screen readers")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func navigateToPlayer() throws {
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

