import Foundation
import AVFoundation
import UIKit

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
                let rawPath = entry.path.hasPrefix("/") ? String(entry.path.dropFirst()) : entry.path
                let fileName: String
                let audioFileURL: URL
                do {
                    fileName = try SafeImportPath.normalizedRelativePath(rawPath)
                    audioFileURL = try SafeImportPath.existingFileURL(for: fileName, inside: folderURL)
                } catch {
                    print("⚠️ FolderImporter: Rejected unsafe audio path: \(entry.path)")
                    continue
                }
                let chapterTitle = generateChapterTitle(from: fileName, index: index + 1)
                
                // Verify the audio file exists
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
        let audioFiles = FolderImporter.audioFiles(in: folderURL)
        
        guard !audioFiles.isEmpty else {
            print("❌ FolderImporter: No audio files found in folder")
            return nil
        }
        
        print("🎵 FolderImporter: Found \(audioFiles.count) audio files")
        
        return await makeFolderAudiobook(from: audioFiles, folderURL: folderURL)
    }

    /// Builds a single audiobook whose chapters are `audioFiles`, in the order given.
    /// `folderURL` only supplies the title, author and cover art, so the caller may pass a folder
    /// it can name but not enumerate, such as the parent of a hand-picked file selection.
    /// - Parameter onFileAnalyzed: reports each file as its duration is read, so a caller driving a
    ///   long selection can show progress. Called off the main actor.
    static func makeFolderAudiobook(
        from audioFiles: [URL],
        folderURL: URL,
        onFileAnalyzed: ((Int, String) -> Void)? = nil
    ) async -> FolderAudiobook? {
        guard !audioFiles.isEmpty else { return nil }

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
                onFileAnalyzed?(result.index, result.fileName)
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
        
        // Prefer the folder artwork. A hand-picked file selection carries no access to its folder,
        // so fall back to the artwork embedded in the first file.
        var coverImage = await findCoverImage(in: folderURL)
        if coverImage == nil {
            coverImage = await MetadataExtractor.extractMetadata(from: audioFiles[0])?.coverImage
        }
        
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
    }
}
