//
//  AudiobookReaderTests.swift
//  AudiobookReaderTests
//
//  Created by Jonathan Jayet on 14/08/2025.
//

import Testing
import Foundation
@testable import AudiobookReader

/// Main test suite for AudiobookReader application
/// This file serves as the entry point for the comprehensive test infrastructure
@MainActor
struct AudiobookReaderTests {

    @Test("Test infrastructure should be properly configured")
    func testInfrastructureConfiguration() async throws {
        // Verify test configuration is set up correctly
        #expect(TestConfiguration.testTimeout > 0)
        #expect(TestConfiguration.performanceTimeout > 0)
        #expect(TestConfiguration.audioEngineTimeout > 0)
        #expect(TestConfiguration.swiftDataTimeout > 0)
        
        // Verify test environment detection
        #expect(ProcessInfo.isRunningTests == true)
        #expect(ProcessInfo.isPreview == false)
        
        // Verify test bundle is accessible
        let testBundle = TestConfiguration.testBundle
        #expect(testBundle.bundleIdentifier != nil)
    }
    
    @Test("Mock framework should be available")
    func mockFrameworkAvailability() async throws {
        // Test mock file manager
        MockFileManager.reset()
        MockFileManager.setFileExists("/test/path", exists: true)
        #expect(MockFileManager.mockFileExists["/test/path"] == true)
        
        // Test mock audio session
        MockAVAudioSession.reset()
        #expect(MockAVAudioSession.shouldFailSetup == false)
        #expect(MockAVAudioSession.preferredSampleRate == 44100.0)

        
        // Test data factory
        let testURL = TestDataFactory.createMockAudioFile(named: "test", duration: 1800)
        #expect(FileManager.default.fileExists(atPath: testURL.path))
    }
    
    @Test("Test data resources should be accessible")
    func testResourcesAccessibility() async throws {
        // This test verifies that our test resource structure is properly set up
        // In a real implementation, you would check for actual test resource files
        
        let tempAudioURL = TestDataFactory.createMockAudioFile(named: "resource-test", duration: 300)
        #expect(FileManager.default.fileExists(atPath: tempAudioURL.path))
        
        let tempCUEURL = TestDataFactory.createMockCUEFile(named: "resource-cue-test", content: "FILE \"test.mp3\" MP3")
        #expect(FileManager.default.fileExists(atPath: tempCUEURL.path))
        
        // Cleanup
        TestDataFactory.cleanupTempFiles()
    }
}
