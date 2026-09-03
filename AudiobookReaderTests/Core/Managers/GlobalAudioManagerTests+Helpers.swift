//
//  GlobalAudioManagerTests+Helpers.swift
//  AudiobookReaderTests
//
//  Split from GlobalAudioManagerTests.swift
//

import Foundation
@testable import AudiobookReader

// MARK: - Helper Methods (shared by GlobalAudioManagerTests and GlobalAudioManagerTests.Part2)

func createTestAudiobook(isMultiFile: Bool, title: String = "Test Audiobook") -> AudiobookModel {
    AudiobookModel(title: title, author: "Test Author", duration: 3600.0)
}

func createTempAudioFile(named filename: String) -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent(filename)
    
    // Create empty file
    FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
    
    return fileURL
}

func createTempDirectory(named dirname: String) -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let dirURL = tempDir.appendingPathComponent(dirname)
    
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    
    return dirURL
}
