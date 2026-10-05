import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    // MARK: - CUE-based Audiobook Import
    
    nonisolated func importCUEBasedAudiobook(audioFile: URL, cueFile: CUEFile) async {
        Log.library.debug("🎵 AudiobookManager: Starting CUE-based audiobook import")
        
        // Extract metadata from the audio file
        guard let metadata = await MetadataExtractor.extractMetadata(from: audioFile) else {
            Log.library.error("❌ AudiobookManager: Failed to extract metadata from audio file")
            // Early exit: mark progress handled by outer defer
            return
        }
        
        // Copy the single audio file to documents directory
        guard let localURL = await copyFileToDocuments(from: audioFile) else {
            // Early exit: mark progress handled by outer defer
            return
        }
        
        // Create the model on the main context so it can be safely presented and edited by SwiftUI.
        do {
            try await MainActor.run {
                let context = swiftDataController.context
                let audiobook = AudiobookModel(
                    title: cueFile.title ?? metadata.title,
                    author: cueFile.performer ?? metadata.author,
                    narrator: metadata.narrator,
                    fileURL: AudiobookModel.storedPath(for: localURL),
                    duration: metadata.duration,
                    currentPosition: 0,
                    isFinished: false,
                    coverImageData: metadata.coverImage?.coverJPEGData(),
                    dateAdded: Date(),
                    lastPlayed: Date.distantPast
                )
                context.insert(audiobook)
                for (index, track) in cueFile.tracks.enumerated() {
                    let endTime = (index + 1 < cueFile.tracks.count)
                        ? cueFile.tracks[index + 1].startTime
                        : metadata.duration
                    let chapter = ChapterModel(
                        title: track.title,
                        chapterNumber: Int16(clamping: track.number),
                        startTime: track.startTime,
                        endTime: endTime
                    )
                    chapter.audiobook = audiobook
                    context.insert(chapter)
                }
                try context.save()
                importBatch.append(audiobook)
                fetchAudiobooks()
            }
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            await reportImportFailure(error)
        }
    }
    
    /// Imports one audio file.
    /// - Parameters:
    ///   - fallbackCover: used when the file carries no artwork of its own.
    nonisolated func importAudiobook(from url: URL, fallbackCover: UIImage? = nil) async {
        await MainActor.run { isImporting = true }
        
        Log.library.debug("🔍 AudiobookManager: Starting single file import for: \(url.lastPathComponent)")
        Log.library.debug("   File extension: \(url.pathExtension)")
        Log.library.debug("   File path: \(url.path)")
        
        // Check if file exists and get size
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                Log.library.debug("   File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            } catch {
                Log.library.debug("   ⚠️ Could not get file attributes: \(error)")
            }
        } else {
            Log.library.debug("   ❌ File does not exist at path!")
        }
        
        // Ensure we have security-scoped resource access
        let hasAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // A file the library already holds is either a duplicate to skip, or the missing file
        // of a book that is still in the library and can be put straight back.
        if await resolveExistingEntry(for: url) { return }

        Log.library.debug("🎵 AudiobookManager: Extracting metadata...")
        // Extract metadata
        guard let metadata = await MetadataExtractor.extractMetadata(from: url) else {
            Log.library.error("❌ AudiobookManager: Failed to extract metadata from file")
            await MainActor.run { }
            return
        }
        
        Log.library.debug("✅ AudiobookManager: Metadata extracted successfully:")
        Log.library.debug("   Title: \(metadata.title)")
        Log.library.debug("   Author: \(metadata.author)")
        Log.library.debug("   Duration: \(metadata.duration)s")
        
        // Copy file to documents directory
        guard let localURL = await copyFileToDocuments(from: url) else {
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
        // Extract chapters
        let chapterInfos = await MetadataExtractor.extractChapters(from: localURL)
        
        // Create the model on the main context so cover selection never crosses contexts.
        do {
            try await MainActor.run {
                let context = swiftDataController.context
                let coverImage = metadata.coverImage ?? fallbackCover
                let audiobook = AudiobookModel(
                    title: metadata.title,
                    author: metadata.author,
                    narrator: metadata.narrator,
                    fileURL: AudiobookModel.storedPath(for: localURL),
                    duration: metadata.duration,
                    currentPosition: 0,
                    isFinished: false,
                    coverImageData: coverImage?.coverJPEGData(),
                    dateAdded: Date(),
                    lastPlayed: Date.distantPast
                )
                context.insert(audiobook)
                for chapterInfo in chapterInfos {
                    let chapter = ChapterModel(
                        title: chapterInfo.title,
                        chapterNumber: Int16(clamping: chapterInfo.chapterNumber),
                        startTime: chapterInfo.startTime,
                        endTime: chapterInfo.endTime
                    )
                    chapter.audiobook = audiobook
                    context.insert(chapter)
                }
                try context.save()
                importBatch.append(audiobook)
                // The album tag names the book these chapter files belong to. It is the only
                // place that name survives when a file provider stages each file separately.
                if pendingMergeTitle == nil, let album = metadata.album, !album.isEmpty {
                    pendingMergeTitle = album
                }
                fetchAudiobooks()
            }
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            await reportImportFailure(error)
        }
    }

    /// Called whenever persisting an import failed and its copied audio has been deleted.
    @MainActor
    func reportImportFailure(_ error: Error) {
        // The book and its chapters are still pending in the shared context. Without this the
        // next successful save would persist them, pointing at the audio just deleted.
        swiftDataController.context.rollback()
        importErrorMessage = String(
            format: NSLocalizedString("The audiobook could not be saved: %@", comment: "Import persistence error"),
            error.localizedDescription
        )
    }
}
