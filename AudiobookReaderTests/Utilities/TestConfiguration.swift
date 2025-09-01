//
//  TestConfiguration.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Foundation
import XCTest
import SwiftData
@testable import AudiobookReader

/// Central configuration for test environment and utilities
enum TestConfiguration {
    // MARK: - Timeouts
    static let testTimeout: TimeInterval = 10.0
    static let performanceTimeout: TimeInterval = 5.0
    static let audioEngineTimeout: TimeInterval = 3.0
    static let swiftDataTimeout: TimeInterval = 2.0
    
    // MARK: - Performance Metrics
    static let memoryTestIterations = 100
    static let maxAcceptableLoadTime: TimeInterval = 3.0
    static let maxChapterTransitionTime: TimeInterval = 0.5
    
    // MARK: - Test Data Paths
    static let testResourcesBundle = "AudiobookReaderTestResources"
    static let sampleAudioPath = "TestResources/SampleAudioFiles"
    static let sampleCUEPath = "TestResources/SampleCUEFiles"
    static let sampleZIPPath = "TestResources/SampleZIPFiles"
    static let sampleImagesPath = "TestResources/SampleImages"
    
    // MARK: - Mock Data Configuration
    static let mockAudiobookTitle = "Test Audiobook"
    static let mockAuthor = "Test Author"
    static let mockNarrator = "Test Narrator"
    static let mockDuration: TimeInterval = 3600.0 // 1 hour
    static let mockCurrentPosition: TimeInterval = 450.0 // 7:30
    
    // MARK: - Environment Setup
    static func setupTestEnvironment() {
        // Clear UserDefaults for clean test environment
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        
        // Set up test-specific configurations
        UserDefaults.standard.set(true, forKey: "isTestEnvironment")
        UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
        
        // Disable analytics and crash reporting in tests
        UserDefaults.standard.set(false, forKey: "enableAnalytics")
        UserDefaults.standard.set(false, forKey: "enableCrashReporting")
    }
    
    static func tearDownTestEnvironment() {
        // Clean up test-specific data
        UserDefaults.standard.removeObject(forKey: "isTestEnvironment")
        UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
        UserDefaults.standard.removeObject(forKey: "enableAnalytics")
        UserDefaults.standard.removeObject(forKey: "enableCrashReporting")
    }
    
    // MARK: - Test Bundle Helpers
    static var testBundle: Bundle {
        return Bundle(identifier: "com.audiobookreader.AudiobookReaderTests") ?? Bundle.main
    }
    
    static func pathForTestResource(_ name: String, ofType type: String) -> String? {
        return testBundle.path(forResource: name, ofType: type)
    }
    
    static func urlForTestResource(_ name: String, ofType type: String) -> URL? {
        return testBundle.url(forResource: name, withExtension: type)
    }
}

/// Test environment detection
extension ProcessInfo {
    static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
               UserDefaults.standard.bool(forKey: "isTestEnvironment")
    }
    
    static var isUITest: Bool {
        return ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }
    
    static var isPerformanceTest: Bool {
        return ProcessInfo.processInfo.arguments.contains("-performance-testing")
    }
}

/// XCTestCase extensions for common test patterns
extension XCTestCase {
    
    // MARK: - Async Testing Helpers
    func waitForCondition(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = TestConfiguration.testTimeout,
        description: String = "Condition"
    ) {
        let expectation = XCTestExpectation(description: description)
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if condition() {
                expectation.fulfill()
                timer.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: timeout)
        timer.invalidate()
    }
    
    // MARK: - Memory Leak Testing
    func validateMemoryLeak<T: AnyObject>(
        _ instance: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Memory leak detected: Instance should have been deallocated",
                file: file,
                line: line
            )
        }
    }
    
    // MARK: - SwiftData Testing Helpers
    @MainActor
    func createInMemorySwiftDataController() -> SwiftDataController {
        let controller = SwiftDataController.preview
        return controller
    }
    
    func createTestAudiobook(
        title: String = TestConfiguration.mockAudiobookTitle,
        author: String = TestConfiguration.mockAuthor,
        duration: TimeInterval = TestConfiguration.mockDuration
    ) -> AudiobookModel {
        let audiobook = AudiobookModel(
            title: title,
            author: author,
            narrator: TestConfiguration.mockNarrator,
            fileURL: nil,
            duration: duration,
            currentPosition: 0,
            isFinished: false,
            dateAdded: Date()
        )
        return audiobook
    }
    
    func createTestChapter(
        for audiobook: AudiobookModel,
        title: String = "Test Chapter",
        chapterNumber: Int = 1,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 1800
    ) -> ChapterModel {
        let chapter = ChapterModel(
            title: title,
            chapterNumber: Int16(chapterNumber),
            startTime: startTime,
            endTime: endTime
        )
        chapter.audiobook = audiobook
        return chapter
    }
}
