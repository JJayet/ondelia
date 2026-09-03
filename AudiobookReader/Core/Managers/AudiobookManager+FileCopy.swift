import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    nonisolated func copyFileToDocuments(from sourceURL: URL) async -> URL? {
        let fileManager = FileManager.default
        
        print("🎵 AudiobookManager: Copying file from: \(sourceURL.path)")
        
        // Ensure we have access to the security-scoped resource
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { 
            if hasAccess { 
                sourceURL.stopAccessingSecurityScopedResource() 
                print("🔓 AudiobookManager: Released security-scoped resource access")
            }
        }

        // NOTE: Reverted iCloud handling to simple copy to avoid regressions.
        
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ AudiobookManager: Failed to get documents directory")
            return nil
        }
        
        let audiobooksDirectory = documentsDirectory.appendingPathComponent("Audiobooks")
        
        // Create audiobooks directory if it doesn't exist
        if !fileManager.fileExists(atPath: audiobooksDirectory.path) {
            do {
                try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
                print("✅ AudiobookManager: Created audiobooks directory at: \(audiobooksDirectory.path)")
            } catch {
                print("❌ AudiobookManager: Failed to create audiobooks directory: \(error)")
                return nil
            }
        }
        
        // Create unique filename to avoid conflicts
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension
        let baseName = String(fileName.dropLast(fileExtension.count + 1))
        
        var destinationURL = audiobooksDirectory.appendingPathComponent(fileName)
        var counter = 1
        
        // Find unique filename
        while fileManager.fileExists(atPath: destinationURL.path) {
            let uniqueName = "\(baseName)_\(counter).\(fileExtension)"
            destinationURL = audiobooksDirectory.appendingPathComponent(uniqueName)
            counter += 1
        }
        
        do {
            // Stream copy off the main thread to avoid UI blocking
            try streamCopyFile(from: sourceURL, to: destinationURL)
            // Verify the file was copied successfully
            let sourceAttributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
            let copiedAttributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let sourceSize = sourceAttributes[.size] as? Int64 ?? -1
            let fileSize = copiedAttributes[.size] as? Int64 ?? 0
            guard sourceSize >= 0, sourceSize == fileSize else {
                try? fileManager.removeItem(at: destinationURL)
                throw CocoaError(.fileWriteUnknown)
            }
            print("✅ AudiobookManager: File copied successfully to: \(destinationURL.path)")
            print("   File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            return destinationURL
        } catch {
            print("❌ AudiobookManager: Failed to copy file: \(error)")
            return nil
        }
    }
    
    /// - Parameter sourceFiles: the files to copy, keyed by chapter file name. Pass them when the
    ///   user picked files rather than their folder, since only those URLs are readable then.
    /// - Parameter onFileCopied: reports each copied file, off the main actor.
    nonisolated func copyFolderToDocuments(
        from sourceFolderURL: URL,
        folderAudiobook: FolderAudiobook,
        sourceFiles: [String: URL]? = nil,
        onFileCopied: (@Sendable (Int, String) -> Void)? = nil
    ) async -> URL? {
        let fileManager = FileManager.default
        
        print("📁 AudiobookManager: Copying folder from: \(sourceFolderURL.path)")
        
        // Ensure we have access to the security-scoped resource
        let hasAccess = sourceFolderURL.startAccessingSecurityScopedResource()
        defer { 
            if hasAccess { 
                sourceFolderURL.stopAccessingSecurityScopedResource() 
                print("🔓 AudiobookManager: Released folder security-scoped resource access")
            }
        }
        
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ AudiobookManager: Failed to get documents directory")
            return nil
        }
        
        let audiobooksDirectory = documentsDirectory.appendingPathComponent("Audiobooks")
        
        // Create audiobooks directory if it doesn't exist
        if !fileManager.fileExists(atPath: audiobooksDirectory.path) {
            do {
                try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
            } catch {
                print("❌ AudiobookManager: Failed to create audiobooks directory: \(error)")
                return nil
            }
        }
        
        // Create unique folder name with better duplicate handling
        let originalFolderName = sourceFolderURL.lastPathComponent
        let sanitizedFolderName = originalFolderName.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        var destinationFolderURL = audiobooksDirectory.appendingPathComponent(sanitizedFolderName)
        var counter = 1
        
        // Generate unique name if folder already exists
        while fileManager.fileExists(atPath: destinationFolderURL.path) {
            let uniqueName = "\(sanitizedFolderName) (\(counter))"
            destinationFolderURL = audiobooksDirectory.appendingPathComponent(uniqueName)
            counter += 1
            
            // Prevent infinite loop
            if counter > 100 {
                print("❌ AudiobookManager: Too many duplicate folders, aborting")
                return nil
            }
        }
        
        print("📂 AudiobookManager: Creating destination folder: \(destinationFolderURL.lastPathComponent)")
        
        do {
            // Create destination folder
            try fileManager.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            
            // Copy each audio file from the folder
            var totalCopiedSize: Int64 = 0
            var copiedFiles = 0
            
            for (fileIndex, folderChapter) in folderAudiobook.chapters.enumerated() {
                let sourceFileURL = try sourceFiles?[folderChapter.fileName]
                    ?? SafeImportPath.existingFileURL(
                        for: folderChapter.fileName,
                        inside: sourceFolderURL
                    )
                let fileAccess = sourceFiles == nil ? false : sourceFileURL.startAccessingSecurityScopedResource()
                defer { if fileAccess { sourceFileURL.stopAccessingSecurityScopedResource() } }
                let destinationFileURL = try SafeImportPath.resolvedURL(
                    for: folderChapter.fileName,
                    inside: destinationFolderURL
                )
                
                // Check if source file exists
                guard fileManager.fileExists(atPath: sourceFileURL.path) else {
                    print("⚠️ AudiobookManager: Source file not found: \(folderChapter.fileName)")
                    continue
                }
                
                // If destination file already exists, remove it first
                if fileManager.fileExists(atPath: destinationFileURL.path) {
                    try fileManager.removeItem(at: destinationFileURL)
                }
                
                // Stream copy each file off the main thread
                try fileManager.createDirectory(
                    at: destinationFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try self.streamCopyFile(from: sourceFileURL, to: destinationFileURL)
                let copiedSize = (try fileManager.attributesOfItem(atPath: destinationFileURL.path)[.size] as? Int64) ?? -1
                let sourceSize = (try fileManager.attributesOfItem(atPath: sourceFileURL.path)[.size] as? Int64) ?? -2
                guard copiedSize == sourceSize else { throw CocoaError(.fileWriteUnknown) }
                totalCopiedSize += copiedSize
                copiedFiles += 1
                
                print("   ✅ Copied: \(folderChapter.fileName) (\(ByteCountFormatter.string(fromByteCount: folderChapter.fileSize, countStyle: .file)))")
                
                onFileCopied?(fileIndex, folderChapter.fileName)
            }
            
            // Copy cover image if it exists
            if let coverImage = folderAudiobook.coverImage {
                let coverImageURL = destinationFolderURL.appendingPathComponent("cover.jpg")
                if let imageData = coverImage.jpegData(compressionQuality: 0.8) {
                    try imageData.write(to: coverImageURL)
            print("   🖼️ Saved cover image")
        }
            }
            
            // Create a manifest file to help with playback
            let manifestData = try createFolderManifest(folderAudiobook: folderAudiobook)
            let manifestURL = destinationFolderURL.appendingPathComponent("audiobook_manifest.json")
            try manifestData.write(to: manifestURL)
            
            guard copiedFiles > 0 else {
                print("❌ AudiobookManager: No files were copied successfully")
                // Clean up empty folder
                try? fileManager.removeItem(at: destinationFolderURL)
                return nil
            }
            
            print("✅ AudiobookManager: Folder copied successfully to: \(destinationFolderURL.path)")
            print("   Total size: \(ByteCountFormatter.string(fromByteCount: totalCopiedSize, countStyle: .file))")
            print("   Files: \(copiedFiles)/\(folderAudiobook.chapters.count)")
            
            return destinationFolderURL
            
        } catch {
            print("❌ AudiobookManager: Failed to copy folder: \(error)")
            // Clean up partial copy
            try? fileManager.removeItem(at: destinationFolderURL)
            return nil
        }
    }

    // MARK: - Streaming copy with progress
    nonisolated func streamCopyFile(from: URL, to: URL) throws {
        let fm = FileManager.default
        let readHandle = try FileHandle(forReadingFrom: from)
        var writeHandle: FileHandle?
        do {
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            guard fm.createFile(atPath: to.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            writeHandle = try FileHandle(forWritingTo: to)

            let chunkSize = 512 * 1024 // 512 KB chunks
            while true {
                let data = try autoreleasepool {
                    try readHandle.read(upToCount: chunkSize)
                }
                guard let data, !data.isEmpty else { break }
                try writeHandle?.write(contentsOf: data)
            }
            try writeHandle?.synchronize()
            try readHandle.close()
            try writeHandle?.close()
        } catch {
            try? readHandle.close()
            try? writeHandle?.close()
            try? fm.removeItem(at: to)
            throw error
        }
    }
    
    nonisolated private func createFolderManifest(folderAudiobook: FolderAudiobook) throws -> Data {
        let manifest: [String: Any] = [
            "title": folderAudiobook.title,
            "author": folderAudiobook.author ?? "Unknown Author",
            "narrator": folderAudiobook.narrator ?? "",
            "totalDuration": folderAudiobook.totalDuration,
            "chapters": folderAudiobook.chapters.map { chapter in
                [
                    "title": chapter.title,
                    "fileName": chapter.fileName,
                    "duration": chapter.duration,
                    "startTime": chapter.startTimeInBook,
                    "chapterNumber": chapter.chapterNumber
                ]
            }
        ]
        
        return try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
    }
    
    nonisolated private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
