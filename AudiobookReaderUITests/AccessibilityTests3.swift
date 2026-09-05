//
//  AccessibilityTests3.swift
//  AudiobookReaderUITests
//
//  Split from AccessibilityTests.swift
//

import XCTest

final class AccessibilityTests3: AccessibilityUITestCase {

    // MARK: - Reduced Motion Accessibility
    
    func testReducedMotionCompliance() throws {
        relaunch(with: ["--reduce-motion"])
        
        // Navigate to player
        libraryTab.tap()
        
        let availableTestCells = audiobookRows
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
        relaunch(with: ["--high-contrast"])
        
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5),
                     "Interface should be usable with high contrast")
        
        libraryTab.tap()
        
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Buttons should be visible with high contrast")
        XCTAssertTrue(importButton.isHittable, "Buttons should remain interactive with high contrast")
        
        let availableTestCells = audiobookRows
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
        relaunch(with: ["--invert-colors"])
        
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
        libraryTab.tap()
        
        // Audit all interactive elements
        // Not `app.cells`: SwiftUI wraps each row in an unlabelled collection view cell and
        // puts the label on the button inside it, which the buttons below already cover.
        let interactiveElements = app.buttons.allElementsBoundByIndex +
                                 app.textFields.allElementsBoundByIndex +
                                 app.searchFields.allElementsBoundByIndex
        
        for element in interactiveElements {
            if element.exists && element.isHittable {
                // Every interactive element should be an accessibility element
                
                // Should have meaningful label
                let label = element.label
                let described = "\(element.elementType) '\(element.identifier)'"
                XCTAssertFalse(label.isEmpty,
                              "Interactive element \(described) should have accessibility label")
                XCTAssertFalse(label == "Button" || label == "Cell",
                              "Label of \(described) should be descriptive, not generic")
                
                // Should have appropriate traits
                if element.elementType == .button {
                    XCTAssertTrue(element.isEnabled || !element.isHittable,
                                 "Hittable buttons should be enabled")
                }
            }
        }
    }
    
    private func auditPlayerAccessibility() throws {
        let availableCells = audiobookRows
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
                XCTAssertFalse(tab.label.isEmpty,
                              "Tab should have accessibility label")
            }
        }
        
        // The player audit above leaves its full screen cover up, and a covered tab bar
        // reports no selection.
        if app.buttons[AccessibilityIdentifiers.Player.playPauseButton].exists {
            app.swipeDown()
        }

        // Test navigation between major sections
        let tabs = [libraryTab, settingsTab]
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
}
