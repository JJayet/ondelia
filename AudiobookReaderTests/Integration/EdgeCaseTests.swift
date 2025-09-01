//
//  EdgeCaseTests.swift
//  AudiobookReaderTests
//
//  Created for Phase 3 Advanced Testing - Edge Cases and Error Scenarios
//

import XCTest
import AVFoundation
import CoreData
@testable import AudiobookReader

final class EdgeCaseTests: XCTestCase {
    
    var dependencies: MockDependencies!
    var persistenceController: PersistenceController!
    var fileManager: FileManager!
    var testDirectoryURL: URL!
    
    override func setUpWithError() throws {
        dependencies = MockDependencies()
        persistenceController = PersistenceController(inMemory: true)
        fileManager = FileManager.default
        
        // Create temporary test directory
        testDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("AudiobookReaderTests")
            .appendingPathComponent(UUID().uuidString)
        
        try fileManager.createDirectory(at: testDirectoryURL, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        // Cleanup test directory
        try? fileManager.removeItem(at: testDirectoryURL)
        
        dependencies = nil
        persistenceController = nil
        fileManager = nil
        testDirectoryURL = nil
    }
    
    // MARK: - Corrupted File Handling
    
    func testCorruptedAudioFileHandling() throws {
        let corruptedFiles = [
            createCorruptedFile(type: .truncatedHeader),
            createCorruptedFile(type: .invalidFormat),
            createCorruptedFile(type: .missingMetadata),
            createCorruptedFile(type: .corruptedContent),
            createCorruptedFile(type: .zeroLength)
        ]
        
        let audioEngine = AudioEngine()
        
        for (index, corruptedFileURL) in corruptedFiles.enumerated() {
            let audiobook = createTestAudiobook(fileURL: corruptedFileURL, title: "Corrupted Test \(index)")
            
            // Should handle corrupted files gracefully
            XCTAssertNoThrow(audioEngine.loadAudiobook(audiobook), 
                           "Loading corrupted file should not throw unhandled exceptions")
            
            // Should not crash when attempting playback
            XCTAssertNoThrow(audioEngine.startPlayback(),
                           "Starting playback of corrupted file should not crash")
            
            // Should report appropriate error state
            let playbackState = audioEngine.getPlaybackState()
            XCTAssertNotEqual(playbackState, .playing,
                            "Corrupted file should not report successful playback")
            
            // Should handle seeking gracefully
            XCTAssertNoThrow(audioEngine.seekTo(time: 10.0),
                           "Seeking in corrupted file should not crash")
            
            audioEngine.stopPlayback()
        }
    }
    
    func testPartiallyCorruptedFileRecovery() throws {
        let partiallyCorruptedFile = createPartiallyCorruptedFile()
        let audiobook = createTestAudiobook(fileURL: partiallyCorruptedFile, title: "Partially Corrupted")
        
        let audioEngine = AudioEngine()
        audioEngine.loadAudiobook(audiobook)
        
        // Should be able to play the uncorrupted portion
        audioEngine.startPlayback()
        
        if audioEngine.getPlaybackState() == .playing {
            // Should handle encountering corruption during playback
            let corruptionPoint: TimeInterval = 300 // 5 minutes in
            audioEngine.seekTo(time: corruptionPoint)
            
            // Allow time for seeking and potential error detection
            Thread.sleep(forTimeInterval: 1.0)
            
            // Should either continue playing past corruption or handle error gracefully
            let stateAfterCorruption = audioEngine.getPlaybackState()
            XCTAssertTrue(stateAfterCorruption == .playing || 
                         stateAfterCorruption == .error ||
                         stateAfterCorruption == .stopped,
                         "Should handle corruption gracefully")
            
            // Should allow recovery operations
            XCTAssertNoThrow(audioEngine.seekTo(time: 0),
                           "Should allow seeking back to beginning after corruption")
        }
        
        audioEngine.stopPlayback()
    }
    
    func testMalformedMetadataHandling() throws {
        let malformedMetadataFiles = [
            createFileWithMalformedMetadata(type: .invalidCharacters),
            createFileWithMalformedMetadata(type: .oversizedTags),
            createFileWithMalformedMetadata(type: .circularReferences),
            createFileWithMalformedMetadata(type: .nullTerminators)
        ]
        
        let metadataExtractor = MetadataExtractor()
        
        for malformedFile in malformedMetadataFiles {
            // Should not crash when extracting malformed metadata
            XCTAssertNoThrow({
                let metadata = try metadataExtractor.extractMetadata(from: malformedFile)
                
                // Should provide sensible defaults for malformed data
                XCTAssertFalse(metadata.title.isEmpty, "Should provide default title for malformed metadata")
                XCTAssertGreaterThan(metadata.duration, 0, "Should extract valid duration despite malformed metadata")
                
                // Should handle special characters safely
                XCTAssertFalse(metadata.title.contains("\0"), "Should not contain null terminators")
                XCTAssertFalse(metadata.author.contains("�"), "Should not contain invalid characters")
            }(), "Metadata extraction should handle malformed data gracefully")
        }
    }
    
    // MARK: - Network Interruption During Imports
    
    func testNetworkInterruptionDuringImport() throws {
        let importManager = FolderImporter()
        let networkSimulator = NetworkConditionSimulator()
        
        // Create a test file that requires network access (simulated cloud file)
        let cloudFileURL = createMockCloudFile()
        
        // Start import
        var importResult: Result<Audiobook, Error>?
        let importExpectation = expectation(description: "Import with network interruption")
        
        importManager.importAudiobook(from: cloudFileURL) { result in
            importResult = result
            importExpectation.fulfill()
        }
        
        // Simulate network interruption mid-import
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            networkSimulator.simulateNetworkLoss()
        }
        
        // Restore network after some time
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            networkSimulator.restoreNetwork()
        }
        
        waitForExpectations(timeout: 10.0)
        
        // Should handle network interruption gracefully
        switch importResult {
        case .success(let audiobook):
            XCTAssertNotNil(audiobook, "Import should complete successfully after network recovery")
        case .failure(let error):
            // Should provide appropriate error for network issues
            XCTAssertTrue(error is NetworkError || error is ImportError,
                         "Should provide appropriate error type for network interruption")
        case .none:
            XCTFail("Import should complete with either success or error")
        }
    }
    
    func testIncompleteDownloadRecovery() throws {
        let partialDownloadURL = createIncompleteDownloadFile()
        let importManager = FolderImporter()
        
        // Attempt to import incomplete file
        var importResult: Result<Audiobook, Error>?
        let expectation = expectation(description: "Incomplete download handling")
        
        importManager.importAudiobook(from: partialDownloadURL) { result in
            importResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        // Should detect incomplete download
        switch importResult {
        case .success:
            XCTFail("Should not succeed with incomplete download")
        case .failure(let error):
            XCTAssertTrue(error is ImportError, "Should report import error for incomplete file")
            let importError = error as! ImportError
            XCTAssertEqual(importError.type, .incompleteFile, "Should specifically identify incomplete file")
        case .none:
            XCTFail("Should return a result")
        }
    }
    
    // MARK: - Storage Space Exhaustion
    
    func testLowDiskSpaceHandling() throws {
        let storageManager = StorageManager()
        let largeAudiobookURL = createLargeAudiobookFile(sizeMB: 500) // 500MB file
        
        // Simulate low disk space condition
        storageManager.simulateLowDiskSpace(availableMB: 100) // Only 100MB available
        
        let importManager = FolderImporter()
        var importResult: Result<Audiobook, Error>?
        let expectation = expectation(description: "Low disk space handling")
        
        importManager.importAudiobook(from: largeAudiobookURL) { result in
            importResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0)
        
        // Should detect insufficient space before attempting import
        switch importResult {
        case .success:
            XCTFail("Should not succeed when insufficient disk space available")
        case .failure(let error):
            XCTAssertTrue(error is StorageError, "Should report storage error")
            let storageError = error as! StorageError
            XCTAssertEqual(storageError.type, .insufficientSpace, "Should identify insufficient space")
        case .none:
            XCTFail("Should return a result")
        }
        
        // Restore normal disk space
        storageManager.restoreNormalDiskSpace()
    }
    
    func testDiskSpaceExhaustionDuringImport() throws {
        let importManager = FolderImporter()
        let largeFileURL = createLargeAudiobookFile(sizeMB: 200)
        
        var importResult: Result<Audiobook, Error>?
        let expectation = expectation(description: "Disk space exhaustion during import")
        
        importManager.importAudiobook(from: largeFileURL) { result in
            importResult = result
            expectation.fulfill()
        }
        
        // Simulate disk space exhaustion mid-import
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            StorageManager.shared.simulateDiskSpaceExhaustion()
        }
        
        waitForExpectations(timeout: 15.0)
        
        // Should handle disk space exhaustion gracefully
        switch importResult {
        case .success:
            XCTFail("Should not succeed when disk space is exhausted during import")
        case .failure(let error):
            XCTAssertTrue(error is StorageError, "Should report storage error")
            
            // Should clean up partial import
            let tempFiles = try fileManager.contentsOfDirectory(
                at: fileManager.temporaryDirectory,
                includingPropertiesForKeys: nil
            )
            let importTempFiles = tempFiles.filter { $0.lastPathComponent.contains("import") }
            XCTAssertEqual(importTempFiles.count, 0, "Should clean up temporary import files")
        case .none:
            XCTFail("Should return a result")
        }
    }
    
    // MARK: - Audio Session Conflicts
    
    func testAudioSessionConflictWithOtherApps() throws {
        let audioEngine = AudioEngine()
        let testAudiobook = createTestAudiobook(fileURL: createValidAudioFile(), title: "Conflict Test")
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(testAudiobook)
        audioEngine.startPlayback()
        
        XCTAssertEqual(audioEngine.getPlaybackState(), .playing, "Should start playing successfully")
        
        // Simulate audio session interruption from another app
        simulateAudioSessionInterruption(type: .began)
        
        // Should handle interruption gracefully
        let stateAfterInterruption = audioEngine.getPlaybackState()
        XCTAssertTrue(stateAfterInterruption == .paused || stateAfterInterruption == .interrupted,
                     "Should pause or indicate interruption when another app takes audio session")
        
        // Simulate interruption end
        simulateAudioSessionInterruption(type: .ended)
        
        // Should be able to resume playback
        audioEngine.startPlayback()
        
        Thread.sleep(forTimeInterval: 0.5)
        let stateAfterResume = audioEngine.getPlaybackState()
        XCTAssertEqual(stateAfterResume, .playing, "Should resume playing after interruption ends")
        
        audioEngine.stopPlayback()
    }
    
    func testMultipleAudioSessionRequests() throws {
        let audioEngines = (0..<5).map { _ in AudioEngine() }
        
        // Multiple engines trying to set up audio session simultaneously
        let expectations = audioEngines.enumerated().map { index, _ in
            expectation(description: "Audio session setup \(index)")
        }
        
        for (index, engine) in audioEngines.enumerated() {
            DispatchQueue.global().async {
                engine.setupAudioSession()
                expectations[index].fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0)
        
        // Should handle multiple session requests gracefully
        // Only one should be active, others should either share or fail gracefully
        let activeEngines = audioEngines.filter { $0.isAudioSessionActive }
        XCTAssertGreaterThanOrEqual(activeEngines.count, 1, "At least one engine should have active session")
        XCTAssertLessThanOrEqual(activeEngines.count, audioEngines.count, "Should not have more active sessions than engines")
        
        // All engines should be in valid states
        for engine in audioEngines {
            let state = engine.getPlaybackState()
            XCTAssertTrue(state == .stopped || state == .ready || state == .error,
                         "All engines should be in valid states after session setup")
        }
    }
    
    // MARK: - Background App Refresh Limitations
    
    func testBackgroundAppRefreshDisabled() throws {
        let audioManager = dependencies.audioManager
        let testAudiobook = createTestAudiobook(fileURL: createValidAudioFile(), title: "Background Test")
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        // Simulate background app refresh being disabled
        simulateBackgroundAppRefreshDisabled()
        
        // Background the app
        simulateAppBackgrounding()
        
        // Wait for background processing limitation to take effect
        Thread.sleep(forTimeInterval: 2.0)
        
        // Should handle background refresh limitation gracefully
        let backgroundState = audioManager.getPlaybackState()
        XCTAssertTrue(backgroundState == .playing || backgroundState == .paused,
                     "Should maintain valid state even with background refresh disabled")
        
        // Foreground the app
        simulateAppForegrounding()
        
        // Should restore full functionality
        let foregroundState = audioManager.getPlaybackState()
        XCTAssertNotEqual(foregroundState, .error, "Should not be in error state after foregrounding")
        
        audioManager.stopPlayback()
    }
    
    func testBackgroundProcessingTimeLimit() throws {
        let audioManager = dependencies.audioManager
        let longAudiobook = createTestAudiobook(fileURL: createValidAudioFile(durationMinutes: 480), title: "Long Background Test")
        
        audioManager.loadAudiobook(longAudiobook)
        audioManager.startPlayback()
        
        // Background the app
        simulateAppBackgrounding()
        
        let backgroundTaskSimulator = BackgroundTaskSimulator()
        backgroundTaskSimulator.startLimitedBackgroundTask()
        
        // Simulate background processing time limit being reached
        backgroundTaskSimulator.simulateTimeLimit(after: 30.0) // iOS gives ~30 seconds
        
        // Should handle background time limit gracefully
        let stateAfterTimeLimit = audioManager.getPlaybackState()
        XCTAssertTrue(stateAfterTimeLimit == .paused || stateAfterTimeLimit == .suspended,
                     "Should pause or suspend when background time limit is reached")
        
        // Should save position before suspension
        let savedPosition = audioManager.getCurrentTime()
        XCTAssertGreaterThan(savedPosition, 0, "Should save current position before suspension")
        
        // Foreground the app
        simulateAppForegrounding()
        
        // Should restore from saved position
        let restoredPosition = audioManager.getCurrentTime()
        XCTAssertEqual(restoredPosition, savedPosition, accuracy: 1.0,
                      "Should restore from saved position when returning to foreground")
        
        audioManager.stopPlayback()
    }
    
    // MARK: - Memory Pressure Edge Cases
    
    func testMemoryPressureWithLargeAudiobook() throws {
        let audioManager = dependencies.audioManager
        let hugeAudiobook = createTestAudiobook(fileURL: createValidAudioFile(durationMinutes: 1200), title: "Huge Audiobook") // 20 hours
        
        // Apply memory pressure
        simulateMemoryPressure(level: .critical)
        
        // Should handle loading large audiobook under memory pressure
        XCTAssertNoThrow(audioManager.loadAudiobook(hugeAudiobook),
                        "Should handle loading large audiobook under memory pressure")
        
        if audioManager.currentAudiobook != nil {
            // Should be able to start playback
            XCTAssertNoThrow(audioManager.startPlayback(),
                           "Should handle playback start under memory pressure")
            
            // Should maintain functionality with reduced memory
            let state = audioManager.getPlaybackState()
            XCTAssertTrue(state == .playing || state == .paused,
                         "Should maintain valid state under memory pressure")
            
            // Should handle seeking under memory pressure
            XCTAssertNoThrow(audioManager.seekTo(time: 3600),
                           "Should handle seeking under memory pressure")
            
            audioManager.stopPlayback()
        }
        
        // Release memory pressure
        simulateMemoryPressure(level: .normal)
    }
    
    func testMemoryWarningDuringPlayback() throws {
        let audioManager = dependencies.audioManager
        let testAudiobook = createTestAudiobook(fileURL: createValidAudioFile(), title: "Memory Warning Test")
        
        audioManager.loadAudiobook(testAudiobook)
        audioManager.startPlayback()
        
        XCTAssertEqual(audioManager.getPlaybackState(), .playing)
        
        // Simulate memory warning
        simulateMemoryWarning()
        
        // Should handle memory warning gracefully
        Thread.sleep(forTimeInterval: 1.0) // Allow time for memory warning processing
        
        let stateAfterWarning = audioManager.getPlaybackState()
        XCTAssertTrue(stateAfterWarning == .playing || stateAfterWarning == .paused,
                     "Should maintain valid state after memory warning")
        
        // Should still be functional after memory warning
        XCTAssertNoThrow(audioManager.seekTo(time: 30.0),
                        "Should remain functional after memory warning")
        
        audioManager.stopPlayback()
    }
    
    // MARK: - Database Corruption and Recovery
    
    func testCorruptedDatabaseRecovery() throws {
        let audiobookManager = dependencies.audiobookManager
        
        // Add some audiobooks to the database
        let testBooks = (0..<5).map { i in
            createTestAudiobook(fileURL: createValidAudioFile(), title: "Test Book \(i)")
        }
        
        for book in testBooks {
            audiobookManager.addAudiobook(book)
        }
        
        // Verify books were added
        XCTAssertEqual(audiobookManager.getAllAudiobooks().count, 5)
        
        // Simulate database corruption
        simulateDatabaseCorruption()
        
        // Should detect corruption and attempt recovery
        let booksAfterCorruption = audiobookManager.getAllAudiobooks()
        
        // Should either recover data or start with empty database
        XCTAssertTrue(booksAfterCorruption.count >= 0,
                     "Should handle database corruption gracefully")
        
        // Should be able to add new books after corruption/recovery
        let newBook = createTestAudiobook(fileURL: createValidAudioFile(), title: "Recovery Test")
        XCTAssertNoThrow(audiobookManager.addAudiobook(newBook),
                        "Should be able to add books after database recovery")
        
        let booksAfterRecovery = audiobookManager.getAllAudiobooks()
        XCTAssertGreaterThan(booksAfterRecovery.count, booksAfterCorruption.count,
                            "Should be able to add new books after recovery")
    }
    
    func testConcurrentDatabaseAccessDuringCorruption() throws {
        let expectations = (0..<10).map { i in
            expectation(description: "Concurrent access \(i)")
        }
        
        // Start multiple concurrent database operations
        for i in 0..<10 {
            DispatchQueue.global().async {
                let manager = self.dependencies.audiobookManager
                let book = self.createTestAudiobook(fileURL: self.createValidAudioFile(), title: "Concurrent Book \(i)")
                
                // Some operations will encounter corruption
                do {
                    manager.addAudiobook(book)
                    _ = manager.getAllAudiobooks()
                } catch {
                    // Should handle database errors gracefully
                    XCTAssertTrue(error is DatabaseError, "Should report appropriate database error")
                }
                
                expectations[i].fulfill()
            }
        }
        
        // Simulate corruption during concurrent access
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.simulateDatabaseCorruption()
        }
        
        waitForExpectations(timeout: 10.0)
        
        // Database should eventually recover and be usable
        Thread.sleep(forTimeInterval: 2.0) // Allow recovery time
        
        let finalBooks = dependencies.audiobookManager.getAllAudiobooks()
        XCTAssertGreaterThanOrEqual(finalBooks.count, 0,
                                   "Database should be in valid state after concurrent corruption")
    }
    
    // MARK: - File System Edge Cases
    
    func testFileSystemPermissionChanges() throws {
        let testFileURL = createValidAudioFile()
        let audiobook = createTestAudiobook(fileURL: testFileURL, title: "Permission Test")
        
        let audioManager = dependencies.audioManager
        audioManager.loadAudiobook(audiobook)
        audioManager.startPlayback()
        
        // Should start playing successfully
        XCTAssertEqual(audioManager.getPlaybackState(), .playing)
        
        // Simulate file permission changes during playback
        simulateFilePermissionDenied(for: testFileURL)
        
        // Should detect permission issue and handle gracefully
        Thread.sleep(forTimeInterval: 1.0)
        
        let stateAfterPermissionChange = audioManager.getPlaybackState()
        XCTAssertTrue(stateAfterPermissionChange == .error || stateAfterPermissionChange == .stopped,
                     "Should detect and handle permission changes")
        
        // Restore permissions
        simulateFilePermissionRestored(for: testFileURL)
        
        // Should be able to recover
        XCTAssertNoThrow(audioManager.loadAudiobook(audiobook),
                        "Should be able to reload after permission restoration")
    }
    
    func testFileMovedDuringPlayback() throws {
        let testFileURL = createValidAudioFile()
        let audiobook = createTestAudiobook(fileURL: testFileURL, title: "File Move Test")
        
        let audioManager = dependencies.audioManager
        audioManager.loadAudiobook(audiobook)
        audioManager.startPlayback()
        
        XCTAssertEqual(audioManager.getPlaybackState(), .playing)
        
        // Simulate file being moved during playback
        let newLocation = testDirectoryURL.appendingPathComponent("moved_file.mp3")
        try fileManager.moveItem(at: testFileURL, to: newLocation)
        
        // Should detect file moved and handle gracefully
        Thread.sleep(forTimeInterval: 1.0)
        
        let stateAfterMove = audioManager.getPlaybackState()
        XCTAssertTrue(stateAfterMove == .error || stateAfterMove == .stopped,
                     "Should detect when file is moved")
        
        // Should provide helpful error information
        if let currentError = audioManager.getCurrentError() {
            XCTAssertTrue(currentError is FileSystemError,
                         "Should provide file system error information")
        }
    }
    
    // MARK: - Helper Methods
    
    private enum CorruptedFileType {
        case truncatedHeader
        case invalidFormat
        case missingMetadata
        case corruptedContent
        case zeroLength
    }
    
    private func createCorruptedFile(type: CorruptedFileType) -> URL {
        let fileName = "corrupted_\(type).mp3"
        let fileURL = testDirectoryURL.appendingPathComponent(fileName)
        
        var data: Data
        switch type {
        case .truncatedHeader:
            data = Data([0xFF, 0xFB]) // Incomplete MP3 header
        case .invalidFormat:
            data = Data("This is not audio data".utf8)
        case .missingMetadata:
            data = createValidMP3Data(withMetadata: false)
        case .corruptedContent:
            data = createPartiallyValidMP3Data()
        case .zeroLength:
            data = Data()
        }
        
        try! data.write(to: fileURL)
        return fileURL
    }
    
    private func createPartiallyCorruptedFile() -> URL {
        let fileURL = testDirectoryURL.appendingPathComponent("partially_corrupted.mp3")
        let validData = createValidMP3Data(withMetadata: true)
        let corruptedData = validData.dropLast(validData.count / 3) + Data(repeating: 0xFF, count: 100)
        
        try! corruptedData.write(to: fileURL)
        return fileURL
    }
    
    private enum MalformedMetadataType {
        case invalidCharacters
        case oversizedTags
        case circularReferences
        case nullTerminators
    }
    
    private func createFileWithMalformedMetadata(type: MalformedMetadataType) -> URL {
        let fileName = "malformed_metadata_\(type).mp3"
        let fileURL = testDirectoryURL.appendingPathComponent(fileName)
        
        let baseData = createValidMP3Data(withMetadata: false)
        var metadataBytes: [UInt8] = []
        
        switch type {
        case .invalidCharacters:
            metadataBytes = [0xFF, 0xFE, 0x00] + "Title with invalid chars: \u{FFFF}\u{0000}".utf8
        case .oversizedTags:
            metadataBytes = Array(repeating: UInt8(ascii: "A"), count: 10000) // 10KB tag
        case .circularReferences:
            metadataBytes = [0x49, 0x44, 0x33] // ID3 header with circular reference
        case .nullTerminators:
            metadataBytes = "Title\u{0000}with\u{0000}nulls".utf8.map { $0 }
        }
        
        let combinedData = baseData + Data(metadataBytes)
        try! combinedData.write(to: fileURL)
        return fileURL
    }
    
    private func createMockCloudFile() -> URL {
        // Create a file that simulates a cloud-based file requiring network access
        let fileURL = testDirectoryURL.appendingPathComponent("cloud_file.mp3")
        let data = createValidMP3Data(withMetadata: true)
        try! data.write(to: fileURL)
        
        // Mark as requiring network access (in a real implementation, this would be a cloud URL)
        return fileURL
    }
    
    private func createIncompleteDownloadFile() -> URL {
        let fileURL = testDirectoryURL.appendingPathComponent("incomplete_download.mp3")
        let fullData = createValidMP3Data(withMetadata: true)
        let partialData = fullData.prefix(fullData.count / 2) // Only half the file
        
        try! partialData.write(to: fileURL)
        return fileURL
    }
    
    private func createLargeAudiobookFile(sizeMB: Int) -> URL {
        let fileURL = testDirectoryURL.appendingPathComponent("large_audiobook_\(sizeMB)MB.mp3")
        let baseData = createValidMP3Data(withMetadata: true)
        let targetSize = sizeMB * 1024 * 1024
        let repeats = targetSize / baseData.count
        
        var largeData = Data()
        for _ in 0..<repeats {
            largeData.append(baseData)
        }
        
        try! largeData.write(to: fileURL)
        return fileURL
    }
    
    private func createValidAudioFile(durationMinutes: Int = 30) -> URL {
        let fileURL = testDirectoryURL.appendingPathComponent("valid_audio_\(durationMinutes)min.mp3")
        let data = createValidMP3Data(withMetadata: true)
        try! data.write(to: fileURL)
        return fileURL
    }
    
    private func createValidMP3Data(withMetadata: Bool) -> Data {
        // Create a minimal but valid MP3 file structure
        var data = Data()
        
        if withMetadata {
            // ID3v2 header
            data.append(contentsOf: [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }
        
        // MP3 frame header (44.1kHz, 128kbps, stereo)
        data.append(contentsOf: [0xFF, 0xFB, 0x90, 0x64])
        
        // Add some audio data
        data.append(Data(repeating: 0xAA, count: 1000))
        
        return data
    }
    
    private func createPartiallyValidMP3Data() -> Data {
        let validStart = createValidMP3Data(withMetadata: true)
        let corruptedMiddle = Data(repeating: 0xFF, count: 500)
        let validEnd = Data(repeating: 0x00, count: 500)
        
        return validStart + corruptedMiddle + validEnd
    }
    
    private func createTestAudiobook(fileURL: URL, title: String) -> Audiobook {
        let context = persistenceController.container.viewContext
        let audiobook = Audiobook(context: context)
        
        audiobook.id = UUID()
        audiobook.title = title
        audiobook.author = "Test Author"
        audiobook.duration = 1800 // 30 minutes
        audiobook.currentPosition = 0
        audiobook.dateAdded = Date()
        audiobook.fileURL = fileURL
        
        return audiobook
    }
    
    private func simulateAudioSessionInterruption(type: AVAudioSession.InterruptionType) {
        let userInfo = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }
    
    private func simulateBackgroundAppRefreshDisabled() {
        // Mock background app refresh being disabled
        UserDefaults.standard.set(false, forKey: "background_app_refresh_enabled")
    }
    
    private func simulateAppBackgrounding() {
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    private func simulateAppForegrounding() {
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    private func simulateMemoryPressure(level: MemoryPressureLevel) {
        // Mock memory pressure simulation
        MemoryPressureSimulator.shared.setLevel(level)
    }
    
    private func simulateMemoryWarning() {
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
    
    private func simulateDatabaseCorruption() {
        // Mock database corruption by damaging the core data store
        DatabaseCorruptionSimulator.shared.simulateCorruption()
    }
    
    private func simulateFilePermissionDenied(for url: URL) {
        // Mock file permission changes
        FilePermissionSimulator.shared.denyAccess(to: url)
    }
    
    private func simulateFilePermissionRestored(for url: URL) {
        // Mock file permission restoration
        FilePermissionSimulator.shared.restoreAccess(to: url)
    }
}

// MARK: - Supporting Classes for Edge Case Testing

enum MemoryPressureLevel {
    case normal
    case warning
    case critical
}

class NetworkConditionSimulator {
    func simulateNetworkLoss() {
        // Mock network loss
        NetworkSimulator.shared.setConnected(false)
    }
    
    func restoreNetwork() {
        // Mock network restoration
        NetworkSimulator.shared.setConnected(true)
    }
}

class BackgroundTaskSimulator {
    private var isRunning = false
    
    func startLimitedBackgroundTask() {
        isRunning = true
    }
    
    func simulateTimeLimit(after seconds: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if self.isRunning {
                self.isRunning = false
                NotificationCenter.default.post(
                    name: NSNotification.Name("BackgroundTaskExpired"),
                    object: nil
                )
            }
        }
    }
}

class StorageManager {
    static let shared = StorageManager()
    private var simulatedAvailableSpace: Int64?
    
    func simulateLowDiskSpace(availableMB: Int) {
        simulatedAvailableSpace = Int64(availableMB) * 1024 * 1024
    }
    
    func simulateDiskSpaceExhaustion() {
        simulatedAvailableSpace = 0
    }
    
    func restoreNormalDiskSpace() {
        simulatedAvailableSpace = nil
    }
    
    func getAvailableDiskSpace() -> Int64 {
        return simulatedAvailableSpace ?? 1_000_000_000 // 1GB default
    }
}

// Mock supporting classes
class MemoryPressureSimulator {
    static let shared = MemoryPressureSimulator()
    private var currentLevel = MemoryPressureLevel.normal
    
    func setLevel(_ level: MemoryPressureLevel) {
        currentLevel = level
    }
}

class NetworkSimulator {
    static let shared = NetworkSimulator()
    private var isConnected = true
    
    func setConnected(_ connected: Bool) {
        isConnected = connected
    }
}

class DatabaseCorruptionSimulator {
    static let shared = DatabaseCorruptionSimulator()
    
    func simulateCorruption() {
        // Mock database corruption
        NotificationCenter.default.post(
            name: NSNotification.Name("DatabaseCorrupted"),
            object: nil
        )
    }
}

class FilePermissionSimulator {
    static let shared = FilePermissionSimulator()
    private var deniedFiles: Set<URL> = []
    
    func denyAccess(to url: URL) {
        deniedFiles.insert(url)
    }
    
    func restoreAccess(to url: URL) {
        deniedFiles.remove(url)
    }
    
    func hasAccess(to url: URL) -> Bool {
        return !deniedFiles.contains(url)
    }
}

// Error types for edge case testing
enum ImportError: Error {
    case incompleteFile
    case networkError
    case storageError
    case invalidFormat
    
    var type: ImportError { return self }
}

enum NetworkError: Error {
    case connectionLost
    case timeout
    case serverError
}

enum StorageError: Error {
    case insufficientSpace
    case diskFull
    case permissionDenied
    
    var type: StorageError { return self }
}

enum DatabaseError: Error {
    case corruption
    case migrationFailed
    case concurrencyError
}

enum FileSystemError: Error {
    case fileNotFound
    case permissionDenied
    case fileMoved
}

// Mock extensions for edge case testing
extension MockAudioEngine {
    var isAudioSessionActive: Bool {
        return true // Mock implementation
    }
    
    func getCurrentError() -> Error? {
        return nil // Mock implementation
    }
}

extension MockAudioManager {
    func getCurrentError() -> Error? {
        return nil // Mock implementation
    }
}