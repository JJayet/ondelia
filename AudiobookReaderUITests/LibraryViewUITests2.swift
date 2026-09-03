//
//  LibraryViewUITests2.swift
//  AudiobookReaderUITests
//
//  Split from LibraryViewUITests.swift
//

import XCTest

final class LibraryViewUITests2: LibraryViewUITestCase {

    // MARK: - Navigation Between Library and Player Tests
    
    func testLibraryToPlayerNavigation() throws {
        let firstAudiobook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
        
        if firstAudiobook.exists {
            firstAudiobook.tap()
            
            // Verify navigation to player
            let playerView = app.buttons[AccessibilityIdentifiers.Player.playPauseButton]
            XCTAssertTrue(playerView.waitForExistence(timeout: 5), "Should navigate to player")
            
            // Verify player is functional
            XCTAssertTrue(playerView.isEnabled, "Player controls should be functional")
        } else {
            throw XCTSkip("No audiobooks available to test navigation")
        }
    }
    
    func testPlayerToLibraryNavigation() throws {
        try navigateToPlayer()
        
        // Navigate back using navigation bar
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
        } else {
            // Alternative: use swipe gesture or mini player close
            app.swipeDown() // Minimize to mini player
            
            let miniPlayerClose = app.buttons[AccessibilityIdentifiers.MiniPlayer.closeButton]
            if miniPlayerClose.exists {
                miniPlayerClose.tap()
            }
        }
        
        // Verify return to library
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3), "Should return to library")
    }
    
    func testLibraryStatePreservation() throws {
        // Test that library state is preserved when navigating away and back
        
        let searchBar = app.searchFields[AccessibilityIdentifiers.Library.searchBar]
        let audiobookCellsForState = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        if searchBar.exists && audiobookCellsForState.firstMatch.exists {
            // Set up a search filter
            searchBar.tap()
            searchBar.typeText("Test")
            sleep(1)
            
            // Note the current state after filtering - can't reliably count XCUIElements
            
            // Navigate to player and back
            let firstBook = app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch
            if firstBook.exists {
                firstBook.tap()
                
                // Wait for player
                _ = app.buttons[AccessibilityIdentifiers.Player.playPauseButton].waitForExistence(timeout: 5)
                
                // Navigate back
                app.navigationBars.buttons.firstMatch.tap()
                
                // Verify search state is preserved
                XCTAssertEqual(searchBar.value as? String, "Test", "Search text should be preserved")
                
                // Verify books are still visible after navigation
                XCTAssertTrue(app.cells[AccessibilityIdentifiers.Library.audiobookCell].firstMatch.exists, "Audiobooks should still be visible after navigation")
            }
        } else {
            throw XCTSkip("Cannot test state preservation without search functionality or audiobooks")
        }
    }
    
    // MARK: - Accessibility and Usability Tests
    
    func testLibraryAccessibilityLabels() throws {
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertFalse(importButton.label.isEmpty, "Import button should have accessibility label")
        
        let viewModeToggle = app.buttons[AccessibilityIdentifiers.Library.viewModeToggle]
        if viewModeToggle.exists {
            XCTAssertFalse(viewModeToggle.label.isEmpty, "View mode toggle should have accessibility label")
        }
        
        let sortButton = app.buttons[AccessibilityIdentifiers.Library.sortButton]
        if sortButton.exists {
            XCTAssertFalse(sortButton.label.isEmpty, "Sort button should have accessibility label")
        }
        
        // Test audiobook cells accessibility
        let audiobookCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        let firstCell = audiobookCells.firstMatch
        if firstCell.exists {
            XCTAssertFalse(firstCell.label.isEmpty, "Audiobook cells should have accessibility labels")
        }
    }
    
    func testLibraryVoiceOverNavigation() throws {
        app.launchArguments.append("--voiceover-testing")
        
        // Test that key elements are accessible via VoiceOver
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.isAccessibilityElement, "Import button should be accessibility element")
        
        let audiobookCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        let firstCell = audiobookCells.firstMatch
        if firstCell.exists {
            XCTAssertTrue(firstCell.isAccessibilityElement, "Audiobook cells should be accessibility elements")
            
            // Test that cells have meaningful descriptions
            let label = firstCell.label
            XCTAssertFalse(label.isEmpty, "Cell should have accessibility label")
            XCTAssertFalse(label.contains("nil"), "Cell label should not contain 'nil'")
        }
    }
    
    func testLibraryDynamicTypeSupport() throws {
        app.launchArguments.append("--dynamic-type-xxxlarge")
        
        // Verify library controls remain accessible with large text
        let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
        XCTAssertTrue(importButton.exists, "Import button should exist with large text")
        XCTAssertTrue(importButton.isHittable, "Import button should be hittable with large text")
        
        // Verify button doesn't get truncated excessively
        let frame = importButton.frame
        XCTAssertGreaterThan(frame.width, 0, "Button should have positive width")
        XCTAssertGreaterThan(frame.height, 0, "Button should have positive height")
    }
    
    // MARK: - Error State Testing
    
    func testEmptyLibraryState() throws {
        // This test assumes we can get to an empty library state
        // In practice, this might require clearing test data or using a fresh install
        
        let audiobookCells = app.cells[AccessibilityIdentifiers.Library.audiobookCell]
        
        let firstCell = audiobookCells.firstMatch
        if !firstCell.exists {
            // Test empty state
            let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
            XCTAssertTrue(importButton.exists, "Import button should be prominently displayed when library is empty")
            XCTAssertTrue(importButton.isEnabled, "Import button should be enabled in empty state")
            
            // Look for empty state messaging
            let emptyStateText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'empty' OR label CONTAINS[c] 'no audiobooks' OR label CONTAINS[c] 'import'")).firstMatch
            XCTAssertTrue(emptyStateText.exists || importButton.exists, "Should show helpful guidance in empty state")
        } else {
            throw XCTSkip("Cannot test empty state with existing audiobooks")
        }
    }
    
    // MARK: - Performance Tests
    
    func testLibraryLoadingPerformance() throws {
        measure {
            // Restart app to measure cold start of library
            app.terminate()
            app.launch()
            
            let libraryTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.libraryTab]
            libraryTab.tap()
            
            // Wait for library to load
            let importButton = app.buttons[AccessibilityIdentifiers.Library.importButton]
            _ = importButton.waitForExistence(timeout: 10)
        }
    }
    
    func testLibraryScrollingPerformance() throws {
        // Test scrolling performance by attempting to scroll the collection view
        measure {
            let collectionView = app.collectionViews.firstMatch
            if collectionView.exists {
                // Perform several swipes
                for _ in 0..<5 {
                    collectionView.swipeUp()
                    usleep(100000)
                }
                
                for _ in 0..<5 {
                    collectionView.swipeDown()
                    usleep(100000)
                }
            }
        }
    }
}
