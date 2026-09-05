import Foundation
import UIKit

// MARK: - Timeout Helper
func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T?.self) { group in
        // Add the main operation task
        group.addTask {
            do {
                let result = try await operation()
                return result
            } catch {
                // Return nil on any error to allow timeout to handle it
                return nil
            }
        }
        
        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil // Timeout reached
        }
        
        // Wait for first completion
        for try await result in group {
            group.cancelAll() // Cancel remaining tasks
            
            if let actualResult = result {
                return actualResult
            } else {
                throw TimeoutError()
            }
        }
        
        throw TimeoutError() // Fallback
    }
}

struct TimeoutError: Error {
    let message = "Operation timed out"
    
    var localizedDescription: String {
        return message
    }
}

// MARK: - Complete.json Models
struct CompleteJsonEntry: Codable {
    let channels: Int
    let info: AudioInfo
    let length: Double
    let md5: String
    let mimetype: String
    let modified: String
    let path: String
    let rate: Int
    let size: Int64
}

struct AudioInfo: Codable {
    let bitrate: Int
    let bitrateMode: Int
    let channels: Int
    let encoderSettings: String
    let frameOffset: Int
    let layer: Int
    let length: Double
    let mode: Int
    let padding: Bool
    let protected: Bool
    let sampleRate: Int
    let sketchy: Bool
    let version: Int
    
    enum CodingKeys: String, CodingKey {
        case bitrate
        case bitrateMode = "bitrate_mode"
        case channels
        case encoderSettings = "encoder_settings"
        case frameOffset = "frame_offset"
        case layer
        case length
        case mode
        case padding
        case protected
        case sampleRate = "sample_rate"
        case sketchy
        case version
    }
}

// MARK: - Folder Audiobook Structure
struct FolderAudiobook {
    let title: String
    let author: String?
    let narrator: String?
    let totalDuration: TimeInterval
    let chapters: [FolderChapter]
    let folderPath: String
    let coverImage: UIImage?
}

struct FolderChapter {
    let title: String
    let fileName: String
    let duration: TimeInterval
    let startTimeInBook: TimeInterval // Cumulative start time in the complete audiobook
    let chapterNumber: Int
    let fileSize: Int64
}
