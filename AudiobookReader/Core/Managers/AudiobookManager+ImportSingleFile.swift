import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    // MARK: - CUE-based Audiobook Import
    
    func importCUEBasedAudiobook(audioFile: URL, cueFile: CUEFile) async {
        print("🎵 AudiobookManager: Starting CUE-based audiobook import")
        
        // Extract metadata from the audio file
        guard let metadata = await MetadataExtractor.extractMetadata(from: audioFile) else {
            print("❌ AudiobookManager: Failed to extract metadata from audio file")
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
                    fileURL: localURL.path,
                    duration: metadata.duration,
                    currentPosition: 0,
                    isFinished: false,
                    coverImageData: metadata.coverImage?.jpegData(compressionQuality: 0.8),
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
                        chapterNumber: Int16(track.number),
                        startTime: track.startTime,
                        endTime: endTime
                    )
                    chapter.audiobook = audiobook
                    context.insert(chapter)
                }
                try context.save()
                fetchAudiobooks()
            }
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            reportImportFailure(error)
        }
    }
    
    /// Imports one audio file.
    /// - Parameters:
    ///   - fallbackCover: used when the file carries no artwork of its own.
    ///   - inCoverBatch: when true the audiobook joins `coverBatch` instead of raising the cover
    ///     picker on its own, so a folder split into many books only asks once, at the end.
    func importAudiobook(from url: URL, fallbackCover: UIImage? = nil, inCoverBatch: Bool = false) async {
        await MainActor.run { isImporting = true }
        
        print("🔍 AudiobookManager: Starting single file import for: \(url.lastPathComponent)")
        print("   File extension: \(url.pathExtension)")
        print("   File path: \(url.path)")
        
        // Check if file exists and get size
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("   File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            } catch {
                print("   ⚠️ Could not get file attributes: \(error)")
            }
        } else {
            print("   ❌ File does not exist at path!")
        }
        
        // Ensure we have security-scoped resource access
        let hasAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        print("🎵 AudiobookManager: Extracting metadata...")
        // Extract metadata
        guard let metadata = await MetadataExtractor.extractMetadata(from: url) else {
            print("❌ AudiobookManager: Failed to extract metadata from file")
            await MainActor.run { }
            return
        }
        
        print("✅ AudiobookManager: Metadata extracted successfully:")
        print("   Title: \(metadata.title)")
        print("   Author: \(metadata.author)")
        print("   Duration: \(metadata.duration)s")
        
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
                    fileURL: localURL.path,
                    duration: metadata.duration,
                    currentPosition: 0,
                    isFinished: false,
                    coverImageData: coverImage?.jpegData(compressionQuality: 0.8),
                    dateAdded: Date(),
                    lastPlayed: Date.distantPast
                )
                context.insert(audiobook)
                for chapterInfo in chapterInfos {
                    let chapter = ChapterModel(
                        title: chapterInfo.title,
                        chapterNumber: Int16(chapterInfo.chapterNumber),
                        startTime: chapterInfo.startTime,
                        endTime: chapterInfo.endTime
                    )
                    chapter.audiobook = audiobook
                    context.insert(chapter)
                }
                try context.save()
                if inCoverBatch {
                    coverBatch.append(audiobook)
                } else if coverImage == nil {
                    audiobookNeedingCover = audiobook
                }
                fetchAudiobooks()
            }
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            reportImportFailure(error)
        }
    }

    @MainActor
    private func reportImportFailure(_ error: Error) {
        importErrorMessage = String(
            format: NSLocalizedString("The audiobook could not be saved: %@", comment: "Import persistence error"),
            error.localizedDescription
        )
    }
}
