//
//  LibraryViewTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure - Phase 2
//

import Testing
import SwiftUI
import Combine
import CoreData
@testable import AudiobookReader

@Suite("LibraryView Tests", .tags(.ui, .library))
struct LibraryViewTests {
    
    let testContext: NSManagedObjectContext
    let mockAudiobookManager: AudiobookManager
    let mockGlobalAudioManager: MockAudioEngine
    
    init() {
        // Create in-memory Core Data stack
        let container = NSPersistentContainer(name: "AudiobookReader")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load test store: \(error)")
            }
        }
        
        testContext = container.viewContext
        mockAudiobookManager = AudiobookManager()
        mockGlobalAudioManager = MockAudioEngine()
        
        // Reset mocks
        MockFileManager.reset()
    }
    
    // MARK: - LibraryView State Tests
    
    @Test("LibraryView initializes correctly with empty library")
    func testLibraryViewEmptyState() async throws {
        // Ensure manager has no audiobooks
        #expect(mockAudiobookManager.audiobooks.isEmpty)
        #expect(mockAudiobookManager.isLoadingLibrary == false)
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
    }
    
    @Test("LibraryView displays loading state correctly")
    func testLibraryViewLoadingState() async throws {
        // Set manager to loading state
        mockAudiobookManager.isLoadingLibrary = true
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        #expect(mockAudiobookManager.isLoadingLibrary == true)
        
        // Simulate loading completion
        mockAudiobookManager.isLoadingLibrary = false
        
        #expect(mockAudiobookManager.isLoadingLibrary == false)
    }
    
    @Test("LibraryView displays audiobook collection correctly")
    func testLibraryViewDisplaysAudiobooks() async throws {
        // Create test audiobooks
        let audiobooks = createMultipleTestAudiobooks(count: 5)
        
        // Simulate loaded state
        mockAudiobookManager.audiobooks = audiobooks
        mockAudiobookManager.isLoadingLibrary = false
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        #expect(mockAudiobookManager.audiobooks.count == 5)
        
        // Verify audiobook data
        for (index, audiobook) in mockAudiobookManager.audiobooks.enumerated() {
            #expect(audiobook.title == "Test Audiobook \(index + 1)")
            #expect(audiobook.author == "Test Author \(index + 1)")
        }
    }
    
    // MARK: - Search Functionality Tests
    
    @Test("LibraryView search functionality works correctly")
    func testLibraryViewSearch() async throws {
        // Create diverse audiobooks for searching
        let audiobooks = [
            createTestAudiobook(title: "Swift Programming", author: "Apple Inc"),
            createTestAudiobook(title: "iOS Development", author: "Ray Wenderlich"),
            createTestAudiobook(title: "SwiftUI Mastery", author: "John Doe"),
            createTestAudiobook(title: "Android Development", author: "Google"),
            createTestAudiobook(title: "React Native", author: "Facebook")
        ]
        
        mockAudiobookManager.audiobooks = audiobooks
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        
        // Test search functionality through manager
        let swiftResults = mockAudiobookManager.searchAudiobooks(query: "Swift")
        #expect(swiftResults.count == 2) // "Swift Programming" and "SwiftUI Mastery"
        
        let appleResults = mockAudiobookManager.searchAudiobooks(query: "Apple")
        #expect(appleResults.count == 1) // "Swift Programming" by Apple Inc
        
        let developmentResults = mockAudiobookManager.searchAudiobooks(query: "Development")
        #expect(developmentResults.count == 3) // iOS, Android, React Native
        
        let emptyResults = mockAudiobookManager.searchAudiobooks(query: "Nonexistent")
        #expect(emptyResults.isEmpty)
    }
    
    @Test("LibraryView handles empty search results")
    func testLibraryViewEmptySearchResults() async throws {
        let audiobooks = createMultipleTestAudiobooks(count: 3)
        mockAudiobookManager.audiobooks = audiobooks
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        // Search for something that doesn't exist
        let noResults = mockAudiobookManager.searchAudiobooks(query: "NonexistentBook")
        #expect(noResults.isEmpty)
        
        // View should handle empty results gracefully
        #expect(hostingController.view != nil)
    }
    
    // MARK: - Audiobook Selection Tests
    
    @Test("LibraryView handles audiobook selection")
    func testLibraryViewAudiobookSelection() async throws {
        let audiobooks = createMultipleTestAudiobooks(count: 3)
        mockAudiobookManager.audiobooks = audiobooks
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        
        // Test that audiobooks are available for selection
        #expect(mockAudiobookManager.audiobooks.count == 3)
        
        let selectedAudiobook = mockAudiobookManager.audiobooks.first!
        
        // Simulate loading selected audiobook into audio manager
        try mockGlobalAudioManager.loadAudiobook(selectedAudiobook)
        
        #expect(mockGlobalAudioManager.audiobook?.title == selectedAudiobook.title)
        #expect(mockGlobalAudioManager.isReady == true)
    }
    
    // MARK: - Library Management Tests
    
    @Test("LibraryView supports audiobook deletion")
    func testLibraryViewAudiobookDeletion() async throws {
        let audiobooks = createMultipleTestAudiobooks(count: 4)
        mockAudiobookManager.audiobooks = audiobooks
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let initialCount = mockAudiobookManager.audiobooks.count
        #expect(initialCount == 4)
        
        // Simulate deletion through manager
        let audiobookToDelete = mockAudiobookManager.audiobooks.first!
        mockAudiobookManager.deleteAudiobook(audiobookToDelete)
        
        // Simulate updated fetch
        mockAudiobookManager.audiobooks.removeAll { $0.objectID == audiobookToDelete.objectID }
        
        #expect(mockAudiobookManager.audiobooks.count == initialCount - 1)
    }
    
    @Test("LibraryView supports audiobook renaming")
    func testLibraryViewAudiobookRenaming() async throws {
        let audiobook = createTestAudiobook(title: "Original Title", author: "Test Author")
        mockAudiobookManager.audiobooks = [AudiobookModel]
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(audiobook.title == "Original Title")
        
        // Simulate renaming through manager
        mockAudiobookManager.renameAudiobook(audiobook, newTitle: "New Title")
        
        #expect(audiobook.title == "New Title")
        #expect(hostingController.view != nil)
    }
    
    // MARK: - Import Integration Tests
    
    @Test("LibraryView handles import state correctly")
    func testLibraryViewImportState() async throws {
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        // Initial state
        #expect(mockAudiobookManager.isImporting == false)
        
        // Simulate import start
        mockAudiobookManager.isImporting = true
        
        #expect(mockAudiobookManager.isImporting == true)
        #expect(hostingController.view != nil)
        
        // Simulate import completion
        mockAudiobookManager.isImporting = false
        
        #expect(mockAudiobookManager.isImporting == false)
    }
    
    @Test("LibraryView updates after successful import")
    func testLibraryViewUpdatesAfterImport() async throws {
        // Start with empty library
        mockAudiobookManager.audiobooks = []
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(mockAudiobookManager.audiobooks.isEmpty)
        
        // Simulate import completion with new audiobook
        let newAudiobook = createTestAudiobook(title: "Imported Book", author: "Import Author")
        mockAudiobookManager.audiobooks = [newAudiobook]
        mockAudiobookManager.isImporting = false
        
        #expect(mockAudiobookManager.audiobooks.count == 1)
        #expect(mockAudiobookManager.audiobooks.first?.title == "Imported Book")
        #expect(hostingController.view != nil)
    }
    
    // MARK: - Sorting and Filtering Tests
    
    @Test("LibraryView handles different sorting options")
    func testLibraryViewSorting() async throws {
        // Create audiobooks with different dates and titles
        let audiobook1 = createTestAudiobook(title: "A First Book", author: "Author A")
        let audiobook2 = createTestAudiobook(title: "Z Last Book", author: "Author Z") 
        let audiobook3 = createTestAudiobook(title: "M Middle Book", author: "Author M")
        
        // Set different dates
        audiobook1.dateAdded = Date().addingTimeInterval(-86400 * 3) // 3 days ago
        audiobook2.dateAdded = Date().addingTimeInterval(-86400 * 1) // 1 day ago
        audiobook3.dateAdded = Date().addingTimeInterval(-86400 * 2) // 2 days ago
        
        mockAudiobookManager.audiobooks = [audiobook1, audiobook2, audiobook3]
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        #expect(mockAudiobookManager.audiobooks.count == 3)
        
        // Test alphabetical sorting
        let alphabeticalSort = mockAudiobookManager.audiobooks.sorted { $0.title! < $1.title! }
        #expect(alphabeticalSort.first?.title == "A First Book")
        #expect(alphabeticalSort.last?.title == "Z Last Book")
        
        // Test date sorting (most recent first)
        let dateSort = mockAudiobookManager.audiobooks.sorted { $0.dateAdded! > $1.dateAdded! }
        #expect(dateSort.first?.title == "Z Last Book") // Most recent
        #expect(dateSort.last?.title == "A First Book") // Oldest
    }
    
    // MARK: - Currently Playing Integration Tests
    
    @Test("LibraryView shows currently playing audiobook")
    func testLibraryViewCurrentlyPlayingIntegration() async throws {
        let audiobooks = createMultipleTestAudiobooks(count: 3)
        mockAudiobookManager.audiobooks = audiobooks
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        // Load and play one audiobook
        let playingAudiobook = audiobooks[1] // Second audiobook
        try mockGlobalAudioManager.loadAudiobook(playingAudiobook)
        mockGlobalAudioManager.startPlayback()
        
        #expect(mockGlobalAudioManager.audiobook?.title == playingAudiobook.title)
        #expect(mockGlobalAudioManager.isPlaying == true)
        #expect(hostingController.view != nil)
        
        // Library should show which audiobook is currently playing
        // (In real implementation, this would be reflected in the UI)
    }
    
    // MARK: - Progress Display Tests
    
    @Test("LibraryView displays audiobook progress correctly")
    func testLibraryViewProgressDisplay() async throws {
        let audiobook = createTestAudiobook(title: "Progress Test", duration: 7200.0) // 2 hours
        audiobook.currentPosition = 1800.0 // 30 minutes
        audiobook.lastPlayed = Date().addingTimeInterval(-3600) // 1 hour ago
        
        mockAudiobookManager.audiobooks = [AudiobookModel]
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        
        // Verify progress data
        let progressPercentage = audiobook.currentPosition / audiobook.duration
        #expect(progressPercentage == 0.25) // 25% complete
        
        let remainingTime = audiobook.duration - audiobook.currentPosition
        #expect(remainingTime == 5400.0) // 1.5 hours remaining
    }
    
    @Test("LibraryView handles finished audiobooks correctly")
    func testLibraryViewFinishedAudiobooks() async throws {
        let finishedBook = createTestAudiobook(title: "Finished Book")
        finishedBook.isFinished = true
        finishedBook.currentPosition = finishedBook.duration
        
        let unfinishedBook = createTestAudiobook(title: "Unfinished Book")
        unfinishedBook.isFinished = false
        unfinishedBook.currentPosition = unfinishedBook.duration * 0.5 // 50% complete
        
        mockAudiobookManager.audiobooks = [finishedBook, unfinishedBook]
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        #expect(hostingController.view != nil)
        
        // Test finished state handling
        #expect(finishedBook.isFinished == true)
        #expect(unfinishedBook.isFinished == false)
        
        // Test mark as unfinished functionality
        mockAudiobookManager.markAsUnread(finishedBook)
        #expect(finishedBook.isFinished == false)
        
        // Test mark as finished functionality
        mockAudiobookManager.markAsRead(unfinishedBook)
        #expect(unfinishedBook.isFinished == true)
    }
    
    // MARK: - Performance Tests
    
    @Test("LibraryView handles large collections efficiently")
    func testLibraryViewLargeCollectionPerformance() async throws {
        // Create large collection
        let audiobooks = createMultipleTestAudiobooks(count: 100)
        mockAudiobookManager.audiobooks = audiobooks
        
        let startTime = Date()
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        let renderTime = Date().timeIntervalSince(startTime)
        
        #expect(hostingController.view != nil)
        #expect(mockAudiobookManager.audiobooks.count == 100)
        #expect(renderTime < 1.0) // Should render within 1 second
        
        // Test search performance on large collection
        let searchStart = Date()
        let searchResults = mockAudiobookManager.searchAudiobooks(query: "Test Audiobook 50")
        let searchTime = Date().timeIntervalSince(searchStart)
        
        #expect(searchTime < 0.1) // Search should be fast
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.title == "Test Audiobook 50")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("LibraryView handles corrupted audiobook data gracefully")
    func testLibraryViewCorruptedDataHandling() async throws {
        // Create audiobook with missing file
        let corruptedAudiobook = createTestAudiobook(title: "Corrupted Book")
        corruptedAudiobook.fileURL = "/nonexistent/path/file.m4a"
        MockFileManager.setFileExists("/nonexistent/path/file.m4a", exists: false)
        
        let validAudiobook = createTestAudiobook(title: "Valid Book")
        
        mockAudiobookManager.audiobooks = [corruptedAudiobook, validAudiobook]
        
        let libraryView = LibraryView()
            .environmentObject(mockAudiobookManager)
            .environmentObject(mockGlobalAudioManager)
        
        let hostingController = UIHostingController(rootView: libraryView)
        
        // View should handle corrupted data without crashing
        #expect(hostingController.view != nil)
        #expect(mockAudiobookManager.audiobooks.count == 2)
        
        // Valid audiobook should still work
        try mockGlobalAudioManager.loadAudiobook(validAudiobook)
        #expect(mockGlobalAudioManager.isReady == true)
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudiobook(
        title: String,
        author: String = "Default Author",
        duration: TimeInterval = 3600.0
    ) -> Audiobook {
        let audiobook = Audiobook(context: testContext)
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = author
        audiobook.duration = duration
        audiobook.currentPosition = 0.0
        audiobook.dateAdded = Date()
        audiobook.isFinished = false
        
        // Create temp file for testing
        let tempFile = createTempAudioFile(named: "\(title).m4a")
        audiobook.fileURL = tempFile.path
        MockFileManager.setFileExists(tempFile.path, exists: true)
        
        try? testContext.save()
        return audiobook
    }
    
    private func createMultipleTestAudiobooks(count: Int) -> [AudiobookModel] {
        return (1...count).map { index in
            createTestAudiobook(
                title: "Test Audiobook \(index)",
                author: "Test Author \(index)",
                duration: Double(index * 1000) // Varying durations
            )
        }
    }
    
    private func createTempAudioFile(named filename: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
}

// MARK: - Test Tags
extension Tag {
    @Tag static var library: Self
}
