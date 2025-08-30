import Foundation

// MARK: - Timeout Helper
func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
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

class FolderImporter {
    
    // MARK: - Import Folder
    static func importAudiobookFolder(from folderURL: URL) async -> FolderAudiobook? {
        print("📁 FolderImporter: Starting import from folder: \(folderURL.lastPathComponent)")
        
        // Ensure we have access to the folder
        let hasAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Look for complete.json
        let completeJsonURL = folderURL.appendingPathComponent("complete.json")
        
        if FileManager.default.fileExists(atPath: completeJsonURL.path) {
            print("✅ FolderImporter: Found complete.json, using structured import")
            return await importFromCompleteJson(folderURL: folderURL, completeJsonURL: completeJsonURL)
        } else {
            print("📄 FolderImporter: No complete.json found, using file-based import")
            return await importFromAudioFiles(folderURL: folderURL)
        }
    }
    
    // MARK: - Import from complete.json
    private static func importFromCompleteJson(folderURL: URL, completeJsonURL: URL) async -> FolderAudiobook? {
        do {
            let jsonData = try Data(contentsOf: completeJsonURL)
            let entries = try JSONDecoder().decode([CompleteJsonEntry].self, from: jsonData)
            
            print("📊 FolderImporter: Found \(entries.count) entries in complete.json")
            
            let folderName = folderURL.lastPathComponent
            let title = extractTitle(from: folderName)
            let author = extractAuthor(from: folderName)
            
            var chapters: [FolderChapter] = []
            var cumulativeTime: TimeInterval = 0
            
            // Sort entries by filename to ensure proper order
            let sortedEntries = entries.sorted { $0.path < $1.path }
            
            for (index, entry) in sortedEntries.enumerated() {
                let fileName = String(entry.path.dropFirst()) // Remove leading "/"
                let chapterTitle = generateChapterTitle(from: fileName, index: index + 1)
                
                // Verify the audio file exists
                let audioFileURL = folderURL.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
                    print("⚠️ FolderImporter: Audio file not found: \(fileName)")
                    continue
                }
                
                let chapter = FolderChapter(
                    title: chapterTitle,
                    fileName: fileName,
                    duration: entry.length,
                    startTimeInBook: cumulativeTime,
                    chapterNumber: index + 1,
                    fileSize: entry.size
                )
                
                chapters.append(chapter)
                cumulativeTime += entry.length
                
                print("📖 FolderImporter: Chapter \(index + 1): \(chapterTitle) (\(formatTime(entry.length)))")
            }
            
            // Look for cover image
            let coverImage = await findCoverImage(in: folderURL)
            
            let folderAudiobook = FolderAudiobook(
                title: title,
                author: author,
                narrator: nil, // Could be extracted from folder name if needed
                totalDuration: cumulativeTime,
                chapters: chapters,
                folderPath: folderURL.path,
                coverImage: coverImage
            )
            
            print("✅ FolderImporter: Successfully created folder audiobook")
            print("   Title: \(title)")
            print("   Author: \(author ?? "Unknown")")
            print("   Duration: \(formatTime(cumulativeTime))")
            print("   Chapters: \(chapters.count)")
            
            return folderAudiobook
            
        } catch {
            print("❌ FolderImporter: Failed to parse complete.json: \(error)")
            return await importFromAudioFiles(folderURL: folderURL)
        }
    }
    
    // MARK: - Import from audio files (fallback)
    private static func importFromAudioFiles(folderURL: URL) async -> FolderAudiobook? {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey])
            
            // Look for CUE files first
            let cueFiles = CUEParser.findCUEFiles(in: folderURL)
            var cueFile: CUEFile?
            var associatedAudioFile: URL?
            
            if let firstCueFile = cueFiles.first {
                print("🎵 FolderImporter: Found CUE file: \(firstCueFile.lastPathComponent)")
                cueFile = CUEParser.parseCUEFile(at: firstCueFile)
                
                if let parsedCue = cueFile {
                    associatedAudioFile = CUEParser.matchCUEWithAudioFile(cueFile: parsedCue, in: folderURL)
                }
            }
            
            // If we have a valid CUE file with associated audio, this is a single-file audiobook
            // We should return nil here so the AudiobookManager can import it as a single file instead
            if let _ = cueFile, let audioFile = associatedAudioFile {
                print("📖 FolderImporter: CUE file detected - this should be imported as a single-file audiobook")
                print("   Audio file: \(audioFile.lastPathComponent)")
                print("   ⚠️ Returning nil to trigger single-file import workflow")
                return nil
            }
            
            // Filter for audio files (fallback to original behavior for multiple files)
            let audioExtensions = ["mp3", "m4a", "m4b", "aac", "wav", "flac"]
            let audioFiles = contents.filter { url in
                audioExtensions.contains(url.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            guard !audioFiles.isEmpty else {
                print("❌ FolderImporter: No audio files found in folder")
                return nil
            }
            
            print("🎵 FolderImporter: Found \(audioFiles.count) audio files")
            
            let folderName = folderURL.lastPathComponent
            let title = extractTitle(from: folderName)
            let author = extractAuthor(from: folderName)
            
            var chapters: [FolderChapter] = []
            var cumulativeTime: TimeInterval = 0
            
            // Process files in batches to improve performance and reduce memory pressure
            let batchSize = 3
            for batchStart in stride(from: 0, to: audioFiles.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, audioFiles.count)
                let batch = Array(audioFiles[batchStart..<batchEnd])
                
                print("🔄 FolderImporter: Processing batch \(batchStart / batchSize + 1): files \(batchStart + 1)-\(batchEnd)")
                
                // Process batch in parallel for better performance
                let batchResults = await withTaskGroup(of: (index: Int, duration: TimeInterval, fileName: String, fileSize: Int64).self) { group in
                    for (localIndex, audioFileURL) in batch.enumerated() {
                        let globalIndex = batchStart + localIndex
                        
                        group.addTask {
                            let asset = AVURLAsset(url: audioFileURL)
                            let duration: TimeInterval
                            
                            do {
                                // Use shorter timeout and better error handling
                                let durationCMTime = try await withTimeout(seconds: 3) {
                                    try await asset.load(.duration)
                                }
                                duration = durationCMTime.seconds.isFinite ? durationCMTime.seconds : 0
                            } catch is TimeoutError {
                                print("⏱️ FolderImporter: Timeout on \(audioFileURL.lastPathComponent)")
                                duration = 0
                            } catch {
                                print("⚠️ FolderImporter: Error on \(audioFileURL.lastPathComponent): \(error)")
                                duration = 0
                            }
                            
                            // Get file size
                            let attributes = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)
                            let fileSize = attributes?[.size] as? Int64 ?? 0
                            
                            return (index: globalIndex, duration: duration, fileName: audioFileURL.lastPathComponent, fileSize: fileSize)
                        }
                    }
                    
                    var results: [(index: Int, duration: TimeInterval, fileName: String, fileSize: Int64)] = []
                    for await result in group {
                        results.append(result)
                    }
                    return results.sorted { $0.index < $1.index }
                }
                
                // Create chapters from batch results
                for result in batchResults {
                    let chapterTitle = generateChapterTitle(from: result.fileName, index: result.index + 1)
                    
                    let chapter = FolderChapter(
                        title: chapterTitle,
                        fileName: result.fileName,
                        duration: result.duration,
                        startTimeInBook: cumulativeTime,
                        chapterNumber: result.index + 1,
                        fileSize: result.fileSize
                    )
                    
                    chapters.append(chapter)
                    cumulativeTime += result.duration
                    
                    print("📖 FolderImporter: Chapter \(result.index + 1): \(chapterTitle) (\(formatTime(result.duration)))")
                }
                
                // Small delay between batches to prevent overwhelming the system
                if batchEnd < audioFiles.count {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
            
            // Look for cover image
            let coverImage = await findCoverImage(in: folderURL)
            
            let folderAudiobook = FolderAudiobook(
                title: title,
                author: author,
                narrator: nil,
                totalDuration: cumulativeTime,
                chapters: chapters,
                folderPath: folderURL.path,
                coverImage: coverImage
            )
            
            print("✅ FolderImporter: Successfully created folder audiobook from files")
            print("   Title: \(title)")
            print("   Author: \(author ?? "Unknown")")
            print("   Duration: \(formatTime(cumulativeTime))")
            print("   Chapters: \(chapters.count)")
            
            return folderAudiobook
            
        } catch {
            print("❌ FolderImporter: Failed to read folder contents: \(error)")
            return nil
        }
    }

    
    // MARK: - Helper Methods
    private static func extractTitle(from folderName: String) -> String {
        // Try to extract title from folder name like "Author - Title"
        if let dashRange = folderName.range(of: " - ") {
            return String(folderName[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback to folder name
        return folderName
    }
    
    private static func extractAuthor(from folderName: String) -> String? {
        // Try to extract author from folder name like "Author - Title"
        if let dashRange = folderName.range(of: " - ") {
            return String(folderName[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private static func generateChapterTitle(from fileName: String, index: Int) -> String {
        // Remove file extension
        let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        
        // If filename contains meaningful text, use it
        if nameWithoutExtension.count > 10 && !nameWithoutExtension.allSatisfy({ $0.isNumber || $0 == "_" }) {
            return nameWithoutExtension.replacingOccurrences(of: "_", with: " ")
        }
        
        // Otherwise, use generic chapter naming
        return "Chapter \(index)"
    }
    
    private static func findCoverImage(in folderURL: URL) async -> UIImage? {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
        let commonNames = ["cover", "folder", "albumart", "front"]
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey])
            
            // Look for common cover image names first
            for name in commonNames {
                for ext in imageExtensions {
                    let imageURL = folderURL.appendingPathComponent("\(name).\(ext)")
                    if contents.contains(imageURL), let image = UIImage(contentsOfFile: imageURL.path) {
                        print("🖼️ FolderImporter: Found cover image: \(name).\(ext)")
                        return image
                    }
                }
            }
            
            // Fallback to any image file
            for url in contents {
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    if let image = UIImage(contentsOfFile: url.path) {
                        print("🖼️ FolderImporter: Using image: \(url.lastPathComponent)")
                        return image
                    }
                }
            }
        } catch {
            print("⚠️ FolderImporter: Could not search for cover image: \(error)")
        }
        
        return nil
    }
    
    private static func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

import AVFoundation
import UIKit
