//
//  GlobalAudioManagerTests+Helpers.swift
//  IsoraTests
//
//  Split from GlobalAudioManagerTests.swift
//

import Foundation
@testable import Isora

// MARK: - Helper Methods (shared by GlobalAudioManagerTests and GlobalAudioManagerTests.EdgeCases)

func createTestAudiobook(isMultiFile: Bool, title: String = "Test Audiobook") -> AudiobookModel {
    AudiobookModel(title: title, author: "Test Author", duration: 3600.0)
}

/// Prefixed with a UUID so parallel or repeated runs never share a file. Callers remove it.
func createTempAudioFile(named filename: String) -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(filename)")
    
    // Create empty file
    FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
    
    return fileURL
}

func removeTempItems(_ urls: URL...) {
    for url in urls {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A folder book with a manifest, so it produces a real multi-chapter timeline.
/// An empty directory is now a failed load rather than a player with nothing in it, so tests
/// that need a folder book need actual chapter files.
func createTestChapterFolder(named dirname: String, chapters: Int = 3) -> URL {
    let dirURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(dirname)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

    var entries: [[String: Any]] = []
    for index in 0..<chapters {
        let name = String(format: "%02d.m4a", index + 1)
        FileManager.default.createFile(
            atPath: dirURL.appendingPathComponent(name).path,
            contents: Data(),
            attributes: nil
        )
        entries.append(["fileName": name, "duration": TimeInterval(600)])
    }
    if let data = try? JSONSerialization.data(withJSONObject: ["chapters": entries]) {
        try? data.write(to: dirURL.appendingPathComponent("audiobook_manifest.json"))
    }
    return dirURL
}
