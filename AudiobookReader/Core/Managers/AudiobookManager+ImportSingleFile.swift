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
        
        // Create audiobook entity (single file, not folder)
        do {
            let bg = swiftDataController.backgroundContext()
            let audiobook = AudiobookModel(
                title: cueFile.title ?? metadata.title,
                author: cueFile.performer ?? metadata.author,
                narrator: metadata.narrator,
                fileURL: localURL.path,
                duration: metadata.duration,
                currentPosition: 0,
                isFinished: false,
                coverImageData: nil,
                dateAdded: Date(),
                lastPlayed: Date.distantPast
            )
            if let coverImage = metadata.coverImage {
                audiobook.coverImageData = coverImage.jpegData(compressionQuality: 0.8)
            }
            for (index, track) in cueFile.tracks.enumerated() {
                let endTime = (index + 1 < cueFile.tracks.count) ? cueFile.tracks[index + 1].startTime : metadata.duration
                let chapter = ChapterModel(
                    title: track.title,
                    chapterNumber: Int16(track.number),
                    startTime: track.startTime,
                    endTime: endTime
                )
                chapter.audiobook = audiobook
                bg.insert(chapter)
            }
            bg.insert(audiobook)
            try? bg.save()
        }
        await MainActor.run { fetchAudiobooks() }
    }
    
    func importAudiobook(from url: URL) async {
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
        
        // Create audiobook entity
        do {
            let bg = swiftDataController.backgroundContext()
            let audiobook = AudiobookModel(
                title: metadata.title,
                author: metadata.author,
                narrator: metadata.narrator,
                fileURL: localURL.path,
                duration: metadata.duration,
                currentPosition: 0,
                isFinished: false,
                coverImageData: nil,
                dateAdded: Date(),
                lastPlayed: Date.distantPast
            )
            if let coverImage = metadata.coverImage {
                audiobook.coverImageData = coverImage.jpegData(compressionQuality: 0.8)
            } else {
                await MainActor.run { self.audiobookNeedingCover = audiobook }
            }
            for chapterInfo in chapterInfos {
                let chapter = ChapterModel(
                    title: chapterInfo.title,
                    chapterNumber: Int16(chapterInfo.chapterNumber),
                    startTime: chapterInfo.startTime,
                    endTime: chapterInfo.endTime
                )
                chapter.audiobook = audiobook
                bg.insert(chapter)
            }
            bg.insert(audiobook)
            try? bg.save()
        }
        await MainActor.run { fetchAudiobooks() }
    }
}
