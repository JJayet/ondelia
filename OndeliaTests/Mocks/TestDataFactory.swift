//
//  TestDataFactory.swift
//  IsoraTests
//
//  Split from MockFramework.swift
//

import Foundation

// MARK: - Test Utilities
class TestDataFactory {
    
    static func createMockAudioFile(named name: String, duration: TimeInterval = 3600) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).m4a")
        
        // Create empty file for testing
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    static func createMockCUEFile(named name: String, content: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).cue")
        
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    static func createMockZIPFile(named name: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(name).zip")
        
        // Create mock ZIP file with empty data
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        return fileURL
    }
    
    static func cleanupTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        for item in (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
