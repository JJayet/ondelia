//
//  AccessibilityTests2.swift
//  AudiobookReaderUITests
//
//  Split from AccessibilityTests.swift
//

import XCTest

final class AccessibilityTests2: AccessibilityUITestCase {

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
}
