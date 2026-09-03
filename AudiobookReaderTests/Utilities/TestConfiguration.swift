//
//  TestConfiguration.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Foundation
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
