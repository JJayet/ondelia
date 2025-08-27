import Foundation
import CoreData
import UIKit

class AudiobookManager: ObservableObject {
    private let persistenceController = PersistenceController.shared
    
    @Published var audiobooks: [Audiobook] = []
    @Published var isImporting = false
    @Published var audiobookNeedingCover: Audiobook?
    
    init() {
        fetchAudiobooks()
    }
    
    // MARK: - Fetch Operations
    func fetchAudiobooks() {
        let request: NSFetchRequest<Audiobook> = Audiobook.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Audiobook.lastPlayed, ascending: false),
                                 NSSortDescriptor(keyPath: \Audiobook.dateAdded, ascending: false)]
        
        do {
            let fetchedAudiobooks = try persistenceController.context.fetch(request)
            
            // Validate file existence and filter out missing files
            var validAudiobooks: [Audiobook] = []
            for audiobook in fetchedAudiobooks {
                if validateAudiobookFile(audiobook) {
                    validAudiobooks.append(audiobook)
                } else {
                    print("⚠️ AudiobookManager: File missing for '\(audiobook.title ?? "Unknown")', removing from library")
                    persistenceController.context.delete(audiobook)
                }
            }
            
            audiobooks = validAudiobooks
            
            // Save context if any books were removed
            if validAudiobooks.count != fetchedAudiobooks.count {
                persistenceController.save()
            }
        } catch {
            print("❌ AudiobookManager: Failed to fetch audiobooks: \(error)")
        }
    }
    
    private func validateAudiobookFile(_ audiobook: Audiobook) -> Bool {
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else {
            print("⚠️ AudiobookManager: No file path for audiobook '\(audiobook.title ?? "Unknown")'")
            return false
        }
        
        let fileExists = FileManager.default.fileExists(atPath: filePath)
        if !fileExists {
            print("⚠️ AudiobookManager: File does not exist at path: \(filePath)")
        }
        
        return fileExists
    }
    
    // MARK: - Import Operations
    func importAudiobookFolder(from folderURL: URL) async {
        await MainActor.run {
            isImporting = true
        }
        
        print("📁 AudiobookManager: Starting folder import from: \(folderURL.lastPathComponent)")
        
        guard let folderAudiobook = await FolderImporter.importAudiobookFolder(from: folderURL) else {
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
        // Copy the entire folder to documents directory
        guard let localFolderURL = await copyFolderToDocuments(from: folderURL, folderAudiobook: folderAudiobook) else {
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
        // Create audiobook entity with multiple files
        await MainActor.run {
            let context = persistenceController.context
            let audiobook = Audiobook(context: context)
            
            audiobook.id = UUID()
            audiobook.title = folderAudiobook.title
            audiobook.author = folderAudiobook.author ?? "Unknown Author"
            audiobook.narrator = folderAudiobook.narrator
            audiobook.duration = folderAudiobook.totalDuration
            audiobook.fileURL = localFolderURL.path // Store folder path instead of single file
            audiobook.dateAdded = Date()
            audiobook.currentPosition = 0
            audiobook.isFinished = false
            
            if let coverImage = folderAudiobook.coverImage {
                audiobook.coverImageData = coverImage.jpegData(compressionQuality: 0.8)
            }
            
            // Add chapters from folder structure
            for folderChapter in folderAudiobook.chapters {
                let chapter = Chapter(context: context)
                chapter.id = UUID()
                chapter.title = folderChapter.title
                chapter.startTime = folderChapter.startTimeInBook
                chapter.endTime = folderChapter.startTimeInBook + folderChapter.duration
                chapter.chapterNumber = Int16(folderChapter.chapterNumber)
                chapter.audiobook = audiobook
            }
            
            print("✅ AudiobookManager: Created multi-file audiobook record:")
            print("   Title: \(folderAudiobook.title)")
            print("   Author: \(folderAudiobook.author ?? "Unknown")")
            print("   Duration: \(formatTime(folderAudiobook.totalDuration))")
            print("   Chapters: \(folderAudiobook.chapters.count)")
            print("   Folder Path: \(localFolderURL.path)")
            
            persistenceController.save()
            fetchAudiobooks()
            isImporting = false
        }
    }
    
    func importAudiobook(from url: URL) async {
        await MainActor.run {
            isImporting = true
        }
        
        // Ensure we have security-scoped resource access
        let hasAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Extract metadata
        guard let metadata = await MetadataExtractor.extractMetadata(from: url) else {
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
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
        await MainActor.run {
            let context = persistenceController.context
            let audiobook = Audiobook(context: context)
            
            audiobook.id = UUID()
            audiobook.title = metadata.title
            audiobook.author = metadata.author
            audiobook.narrator = metadata.narrator
            audiobook.duration = metadata.duration
            audiobook.fileURL = localURL.path
            audiobook.dateAdded = Date()
            audiobook.currentPosition = 0
            audiobook.isFinished = false
            
            print("✅ AudiobookManager: Created audiobook record:")
            print("   Title: \(metadata.title)")
            print("   Author: \(metadata.author)")
            print("   Duration: \(Int(metadata.duration))s")
            print("   File Path: \(localURL.path)")
            
            if let coverImage = metadata.coverImage {
                audiobook.coverImageData = coverImage.jpegData(compressionQuality: 0.8)
            } else {
                audiobookNeedingCover = audiobook
            }
            
            // Add chapters
            for chapterInfo in chapterInfos {
                let chapter = Chapter(context: context)
                chapter.id = UUID()
                chapter.title = chapterInfo.title
                chapter.startTime = chapterInfo.startTime
                chapter.endTime = chapterInfo.endTime
                chapter.chapterNumber = Int16(chapterInfo.chapterNumber)
                chapter.audiobook = audiobook
            }
            
            persistenceController.save()
            fetchAudiobooks()
            isImporting = false
        }
    }
    
    // MARK: - Cover Image Management
    func updateCoverImage(for audiobook: Audiobook, with image: UIImage) {
        audiobook.coverImageData = image.jpegData(compressionQuality: 0.8)
        persistenceController.save()
        fetchAudiobooks()
        
        // Clear the needing cover flag if this was the audiobook that needed it
        if audiobookNeedingCover?.objectID == audiobook.objectID {
            audiobookNeedingCover = nil
        }
    }
    
    private func copyFileToDocuments(from sourceURL: URL) async -> URL? {
        let fileManager = FileManager.default
        
        print("🎵 AudiobookManager: Copying file from: \(sourceURL.path)")
        
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
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            
            // Verify the file was copied successfully
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            print("✅ AudiobookManager: File copied successfully to: \(destinationURL.path)")
            print("   File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            
            return destinationURL
        } catch {
            print("❌ AudiobookManager: Failed to copy file: \(error)")
            return nil
        }
    }
    
    private func copyFolderToDocuments(from sourceFolderURL: URL, folderAudiobook: FolderAudiobook) async -> URL? {
        let fileManager = FileManager.default
        
        print("📁 AudiobookManager: Copying folder from: \(sourceFolderURL.path)")
        
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
        
        // Create unique folder name
        let originalFolderName = sourceFolderURL.lastPathComponent
        var destinationFolderURL = audiobooksDirectory.appendingPathComponent(originalFolderName)
        var counter = 1
        
        while fileManager.fileExists(atPath: destinationFolderURL.path) {
            let uniqueName = "\(originalFolderName)_\(counter)"
            destinationFolderURL = audiobooksDirectory.appendingPathComponent(uniqueName)
            counter += 1
        }
        
        do {
            // Create destination folder
            try fileManager.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            
            // Copy each audio file from the folder
            var totalCopiedSize: Int64 = 0
            
            for folderChapter in folderAudiobook.chapters {
                let sourceFileURL = sourceFolderURL.appendingPathComponent(folderChapter.fileName)
                let destinationFileURL = destinationFolderURL.appendingPathComponent(folderChapter.fileName)
                
                try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
                totalCopiedSize += folderChapter.fileSize
                
                print("   ✅ Copied: \(folderChapter.fileName) (\(ByteCountFormatter.string(fromByteCount: folderChapter.fileSize, countStyle: .file)))")
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
            
            print("✅ AudiobookManager: Folder copied successfully to: \(destinationFolderURL.path)")
            print("   Total size: \(ByteCountFormatter.string(fromByteCount: totalCopiedSize, countStyle: .file))")
            print("   Files: \(folderAudiobook.chapters.count)")
            
            return destinationFolderURL
            
        } catch {
            print("❌ AudiobookManager: Failed to copy folder: \(error)")
            // Clean up partial copy
            try? fileManager.removeItem(at: destinationFolderURL)
            return nil
        }
    }
    
    private func createFolderManifest(folderAudiobook: FolderAudiobook) throws -> Data {
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Progress Management
    func updateProgress(for audiobook: Audiobook, currentTime: TimeInterval) {
        audiobook.currentPosition = currentTime
        audiobook.lastPlayed = Date()
        
        // Mark as finished if within 30 seconds of the end
        if audiobook.duration > 0 && (audiobook.duration - currentTime) <= 30 {
            audiobook.isFinished = true
        }
        
        persistenceController.save()
    }
    
    // MARK: - Bookmark Management
    func createBookmark(for audiobook: Audiobook, at timestamp: TimeInterval, title: String, note: String? = nil) {
        let context = persistenceController.context
        let bookmark = Bookmark(context: context)
        
        bookmark.id = UUID()
        bookmark.title = title
        bookmark.note = note
        bookmark.timestamp = timestamp
        bookmark.dateCreated = Date()
        bookmark.audiobook = audiobook
        
        persistenceController.save()
    }
    
    func deleteBookmark(_ bookmark: Bookmark) {
        persistenceController.context.delete(bookmark)
        persistenceController.save()
    }
    
    // MARK: - Library Management
    func deleteAudiobook(_ audiobook: Audiobook) {
        // Delete physical file
        if let filePath = audiobook.fileURL, !filePath.isEmpty {
            let fileURL = URL(fileURLWithPath: filePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from Core Data
        persistenceController.context.delete(audiobook)
        persistenceController.save()
        fetchAudiobooks()
    }
    
    func searchAudiobooks(query: String) -> [Audiobook] {
        guard !query.isEmpty else { return audiobooks }
        
        return audiobooks.filter { audiobook in
            let title = audiobook.title?.lowercased() ?? ""
            let author = audiobook.author?.lowercased() ?? ""
            let searchQuery = query.lowercased()
            
            return title.contains(searchQuery) || author.contains(searchQuery)
        }
    }
}
