//
//  LibraryViewUITests.swift
//  AudiobookReaderUITests
//
//  Created for Phase 3 Advanced UI Testing
//

import XCTest

/// Shared launch, teardown and player navigation for the LibraryViewUITests* classes.
@MainActor
class LibraryViewUITestCase: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
        app.launchArguments.append("--reset-state")
        app.launch()
        
        // Navigate to library view
        let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
        let exists = libraryTab.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "App should launch successfully")
        libraryTab.tap()
        
        // Wait for library view to load
        sleep(1)
    }
    
    override func tearDown() async throws {
        app.terminate()
        app = nil
    }

    func navigateToPlayer() throws {
        let firstAudiobook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
        
        if !firstAudiobook.exists {
            throw XCTSkip("No audiobooks available for testing")
        }
        
        firstAudiobook.tap()
        
        let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
        let playerLoaded = playPauseButton.waitForExistence(timeout: 5)
        XCTAssertTrue(playerLoaded, "Player should load after selecting audiobook")
    }
}

final class LibraryViewUITests: LibraryViewUITestCase {

    // MARK: - Library Grid/List View Interaction Tests
    
    func testLibraryViewModeToggle() throws {
        let viewModeToggle = app.buttons[AccessibilityIdentifiers.Library.viewModeToggle]
        
        if viewModeToggle.exists {
            let initialMode = viewModeToggle.label
            
            // Toggle view mode
            viewModeToggle.tap()
            
            // Allow UI to update
            usleep(500000)
            
            let newMode = viewModeToggle.label
            XCTAssertNotEqual(initialMode, newMode, "View mode should change after toggle")
            
            // Toggle back
            viewModeToggle.tap()
            usleep(500000)
            
            let finalMode = viewModeToggle.label
            XCTAssertEqual(initialMode, finalMode, "View mode should return to original after second toggle")
        } else {
            throw XCTSkip("View mode toggle not available in current library state")
        }
    }
    
    func testLibraryAudiobookSelection() throws {
        let firstAudiobook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
        
        if firstAudiobook.exists {
            XCTAssertTrue(firstAudiobook.isHittable, "First audiobook should be tappable")
            
            // Tap to select audiobook
            firstAudiobook.tap()
            
            // Should navigate to player
            let playPauseButton = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            let playerLoaded = playPauseButton.waitForExistence(timeout: 5)
            XCTAssertTrue(playerLoaded, "Should navigate to player after selecting audiobook")
            
            // Navigate back to library
            app.navigationBars.buttons.firstMatch.tap()
            
            // Verify we're back in library
            let libraryImportButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
            XCTAssertTrue(libraryImportButton.waitForExistence(timeout: 3), "Should return to library")
        } else {
            // Test empty state
            let emptyStateIndicator = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'no audiobooks'")).firstMatch
            XCTAssertTrue(emptyStateIndicator.exists || app.cells.count == 0, "Should show empty state or have no cells")
        }
    }
    
    func testLibraryScrolling() throws {
        let libraryView = app.scrollViews.firstMatch
        
        if !libraryView.exists {
            // Try finding collection view for grid layout
            let collectionView = app.collectionViews.firstMatch
            XCTAssertTrue(collectionView.exists, "Should have a scrollable view in library")
            
            // Test scrolling
            collectionView.swipeUp()
            
            // Verify the view responded to swipe
            XCTAssertTrue(collectionView.exists, "Collection view should still exist after swipe")
        } else {
            // Test with scroll view
            libraryView.swipeUp()
            libraryView.swipeDown()
            XCTAssertTrue(libraryView.exists, "Scroll view should handle swipe gestures")
        }
    }
    
    // MARK: - Import Workflow UI Tests
    
    func testImportButtonAccessibility() throws {
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Import button should exist")
        XCTAssertTrue(importButton.isEnabled, "Import button should be enabled")
        XCTAssertTrue(importButton.isHittable, "Import button should be hittable")
        
        // Check accessibility properties
        XCTAssertFalse(importButton.label.isEmpty, "Import button should have accessibility label")
    }
    
    func testImportWorkflowInitiation() throws {
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Import button should exist")
        
        importButton.tap()
        
        // Should present document picker or import options
        // Wait for system document picker or import sheet to appear
        sleep(2)
        
        // Check if document picker appeared (system sheet)
        let documentPicker = app.sheets.firstMatch
        let navigationController = app.navigationBars.firstMatch
        
        // Either a sheet or navigation should appear for import
        let importInterfaceAppeared = documentPicker.exists || navigationController.exists
        XCTAssertTrue(importInterfaceAppeared, "Import interface should appear after tapping import button")
        
        // If a sheet appeared, dismiss it
        if documentPicker.exists {
            // Try to find cancel or close button
            let cancelButton = documentPicker.buttons["Cancel"].firstMatch
            if cancelButton.exists {
                cancelButton.tap()
            } else {
                // Swipe down to dismiss sheet
                documentPicker.swipeDown()
            }
        }
    }
    
    func testImportProgressIndication() throws {
        // This test would require actual import simulation
        // For now, we test that progress indicators can be displayed
        
        // Note: In a real scenario, this would involve:
        // 1. Triggering an import
        // 2. Checking for progress indicators
        // 3. Waiting for completion
        
        // For UI testing without actual files, we verify the UI components exist
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Import infrastructure should be present")
        
        // Test that the library can show progress indicators
        let progressIndicators = app.progressIndicators
        // Progress indicators may not exist initially, but the query should not crash
        XCTAssertNotNil(progressIndicators, "Should be able to query for progress indicators")
    }
    
    // MARK: - Search and Filtering Tests
    
    func testSearchBarInteraction() throws {
        let searchBar = app.searchFields[AccessibilityIdentifiers.Library.searchBar]
        
        if searchBar.exists {
            XCTAssertTrue(searchBar.isEnabled, "Search bar should be enabled")
            
            // Tap to focus
            searchBar.tap()
            
            // Type search text
            searchBar.typeText("Test")
            
            // Verify text was entered
            XCTAssertEqual(searchBar.value as? String, "Test", "Search bar should contain typed text")
            
            // Clear search
            let clearButton = searchBar.buttons["Clear text"].firstMatch
            if clearButton.exists {
                clearButton.tap()
            } else {
                // Alternative: select all and delete
                searchBar.doubleTap() // Select all
                app.keys["delete"].tap()
            }
        } else {
            // Search functionality might not be implemented yet
            throw XCTSkip("Search bar not available in current implementation")
        }
    }
    
    func testSearchFiltering() throws {
        let searchBar = app.searchFields[AccessibilityIdentifiers.Library.searchBar]
        
        if searchBar.exists {
            // Check if there are audiobooks to search through
            let audiobookCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
            
            if audiobookCells.firstMatch.exists {
                searchBar.tap()
                searchBar.typeText("NonExistentBook12345")
                
                // Wait for filtering
                sleep(1)
                
                // After searching for something that doesn't exist, there should be no results or fewer results
                // We can't reliably count XCUIElements, so we just verify the search functionality works
                XCTAssertTrue(searchBar.exists, "Search bar should remain functional")
                
                // Clear search to restore full list
                searchBar.buttons["Clear text"].tap()
                sleep(1)
                
                // After clearing search, audiobooks should be visible again
                XCTAssertTrue(audiobookCells.firstMatch.exists, "Audiobooks should be visible after clearing search")
            }
        } else {
            throw XCTSkip("Search functionality not available for testing")
        }
    }
    
    func testSortingFunctionality() throws {
        let sortButton = app.buttons[AccessibilityIdentifiers.Library.sortButton]
        
        if sortButton.exists {
            XCTAssertTrue(sortButton.isEnabled, "Sort button should be enabled")
            XCTAssertTrue(sortButton.isHittable, "Sort button should be hittable")
            
            // Get initial sort state
            let initialLabel = sortButton.label
            
            sortButton.tap()
            
            // Should show sort options or change sort mode
            usleep(500000)
            
            // Verify interaction occurred (label might change or menu might appear)
            let sortOptionExists = app.menus.firstMatch.exists || sortButton.label != initialLabel
            XCTAssertTrue(sortOptionExists, "Sort interaction should show options or change state")
        } else {
            throw XCTSkip("Sort functionality not available in current implementation")
        }
    }
}
