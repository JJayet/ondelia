import Foundation
import AVFoundation
import UIKit

enum FolderImporter {
    
    // MARK: - Import Folder
    static func importAudiobookFolder(from folderURL: URL) async -> FolderAudiobook? {
        Log.library.debug("📁 FolderImporter: Starting import from folder: \(folderURL.lastPathComponent)")
        
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
            Log.library.debug("✅ FolderImporter: Found complete.json, using structured import")
            return await importFromCompleteJson(folderURL: folderURL, completeJsonURL: completeJsonURL)
        } else {
            Log.library.debug("📄 FolderImporter: No complete.json found, using file-based import")
            return await importFromAudioFiles(folderURL: folderURL)
        }
    }
    
    // MARK: - Import from complete.json
    private static func importFromCompleteJson(folderURL: URL, completeJsonURL: URL) async -> FolderAudiobook? {
        do {
            let jsonData = try Data(contentsOf: completeJsonURL)
            let entries = try JSONDecoder().decode([CompleteJsonEntry].self, from: jsonData)
            
            Log.library.debug("📊 FolderImporter: Found \(entries.count) entries in complete.json")
            
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
                    audioFileURL = try SafeImportPath.containedFileURL(for: fileName, inside: folderURL)
                } catch {
                    Log.library.warning("⚠️ FolderImporter: Rejected unsafe audio path: \(entry.path)")
                    continue
                }
                let chapterTitle = generateChapterTitle(from: fileName, index: index + 1)
                
                // Verify the audio file exists
                guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
                    Log.library.warning("⚠️ FolderImporter: Audio file not found: \(fileName)")
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
                
                Log.library.debug("📖 FolderImporter: Chapter \(index + 1): \(chapterTitle) (\(entry.length.clockFormatted))")
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
            
            Log.library.debug("✅ FolderImporter: Successfully created folder audiobook")
            Log.library.debug("   Title: \(title)")
            Log.library.debug("   Author: \(author ?? "Unknown")")
            Log.library.debug("   Duration: \(cumulativeTime.clockFormatted)")
            Log.library.debug("   Chapters: \(chapters.count)")
            
            return folderAudiobook
            
        } catch {
            Log.library.error("❌ FolderImporter: Failed to parse complete.json: \(error)")
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
            Log.library.debug("🎵 FolderImporter: Found CUE file: \(firstCueFile.lastPathComponent)")
            cueFile = CUEParser.parseCUEFile(at: firstCueFile)
            
            if let parsedCue = cueFile {
                associatedAudioFile = CUEParser.matchCUEWithAudioFile(cueFile: parsedCue, in: folderURL)
            }
        }
        
        // If we have a valid CUE file with associated audio, this is a single-file audiobook
        // We should return nil here so the AudiobookManager can import it as a single file instead
        if let _ = cueFile, let audioFile = associatedAudioFile {
            Log.library.debug("📖 FolderImporter: CUE file detected - this should be imported as a single-file audiobook")
            Log.library.debug("   Audio file: \(audioFile.lastPathComponent)")
            Log.library.debug("   ⚠️ Returning nil to trigger single-file import workflow")
            return nil
        }
        
        // Filter for audio files (fallback to original behavior for multiple files)
        let audioFiles = FolderImporter.audioFiles(in: folderURL)
        
        guard !audioFiles.isEmpty else {
            Log.library.error("❌ FolderImporter: No audio files found in folder")
            return nil
        }
        
        Log.library.debug("🎵 FolderImporter: Found \(audioFiles.count) audio files")
        
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
            
            Log.library.debug("🔄 FolderImporter: Processing batch \(batchStart / batchSize + 1): files \(batchStart + 1)-\(batchEnd)")
            
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
                            Log.library.debug("⏱️ FolderImporter: Timeout on \(audioFileURL.lastPathComponent)")
                            duration = 0
                        } catch {
                            Log.library.warning("⚠️ FolderImporter: Error on \(audioFileURL.lastPathComponent): \(error)")
                            duration = 0
                        }
                        
                        // Get file size
                        let attributes = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path)
                        let fileSize = attributes?[.size] as? Int64 ?? 0
                        
                        // Relative, so a chapter living in a subfolder keeps its subfolder in the
                        // manifest and survives the copy into the library.
                        let fileName = FolderImporter.relativePath(of: audioFileURL, in: folderURL)
                        return (index: globalIndex, duration: duration, fileName: fileName, fileSize: fileSize)
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
                
                Log.library.debug("📖 FolderImporter: Chapter \(result.index + 1): \(chapterTitle) (\(result.duration.clockFormatted))")
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
        
        Log.library.debug("✅ FolderImporter: Successfully created folder audiobook from files")
        Log.library.debug("   Title: \(title)")
        Log.library.debug("   Author: \(author ?? "Unknown")")
        Log.library.debug("   Duration: \(cumulativeTime.clockFormatted)")
        Log.library.debug("   Chapters: \(chapters.count)")
        
        return folderAudiobook
    }
}
