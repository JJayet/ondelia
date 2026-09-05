//
//  MockFramework.swift
//  IsoraTests
//
//  Created by Isora Testing Infrastructure
//

import Foundation
import AVFoundation
@testable import Isora

// MARK: - Mock AVAudioSession
@MainActor
class MockAVAudioSession {
    static var shouldFailSetup = false
    static var preferredSampleRate: Double = 44100.0
    static var currentRoute: AVAudioSessionRouteDescription = AVAudioSessionRouteDescription()
    static var isOtherAudioPlaying = false
    
    static func reset() {
        shouldFailSetup = false
        preferredSampleRate = 44100.0
        isOtherAudioPlaying = false
    }
}

// MARK: - Mock FileManager
@MainActor
class MockFileManager {
    static var mockFileExists: [String: Bool] = [:]
    static var mockDirectoryContents: [String: [URL]] = [:]
    static var mockFileSize: [String: Int64] = [:]
    static var shouldFailFileOperations = false
    
    static func reset() {
        mockFileExists.removeAll()
        mockDirectoryContents.removeAll()
        mockFileSize.removeAll()
        shouldFailFileOperations = false
    }
    
    static func setFileExists(_ path: String, exists: Bool) {
        mockFileExists[path] = exists
    }
    
    static func setDirectoryContents(_ path: String, contents: [URL]) {
        mockDirectoryContents[path] = contents
    }
    
    static func setFileSize(_ path: String, size: Int64) {
        mockFileSize[path] = size
    }
}
