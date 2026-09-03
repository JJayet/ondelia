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
}
