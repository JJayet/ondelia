import Foundation
import SwiftData
import UIKit

class AudiobookManager: ObservableObject, AudiobookManagerProtocol {
    private let swiftDataController = SwiftDataController.shared
    
    @Published var audiobooks: [AudiobookModel] = []
    @Published var isImporting = false
    @Published var isLoadingLibrary = false
    @Published var audiobookNeedingCover: AudiobookModel?
    
    private var pendingImports: [(urls: [URL], completion: (() -> Void)?)] = []
    
    func getBookmarks(for audiobook: AudiobookModel) -> [BookmarkModel] {
        return audiobook.bookmarks
    }
    
    func markAsFinished(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
    }
    
    func resetProgress(for audiobook: AudiobookModel) {
        audiobook.currentPosition = 0
    }
    
    func updateProgress(for audiobook: AudiobookModel, currentTime: TimeInterval) {
        audiobook.currentPosition = currentTime
        audiobook.lastPlayed = Date()
        
        // Mark as finished if within 30 seconds of the end
        if audiobook.duration > 0 && (audiobook.duration - currentTime) <= 30 {
            audiobook.isFinished = true
        }
        
        swiftDataController.save()
    }
    
    @MainActor
    func createBookmark(for audiobook: AudiobookModel, at timestamp: TimeInterval, title: String, note: String? = nil) {
        let context = swiftDataController.context
        let bookmark = BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
        
        bookmark.audiobook = audiobook
        context.insert(bookmark)
        
        swiftDataController.save()
    }
    
    @MainActor
    func deleteBookmark(_ bookmark: BookmarkModel) {
        let context = swiftDataController.context
        context.delete(bookmark)
        swiftDataController.save()
    }
    
    
    // MARK: - Fetch Operations
    @MainActor
    func fetchAudiobooks() {
        // Prevent multiple concurrent fetch operations
        guard !isLoadingLibrary else { return }
        isLoadingLibrary = true
        let context = swiftDataController.context
            let descriptor = FetchDescriptor<AudiobookModel>(
                sortBy: [
                    SortDescriptor(\.lastPlayed, order: .reverse),
                    SortDescriptor(\.dateAdded, order: .reverse)
                ]
            )
        do {
            let fetched = try context.fetch(descriptor)
            var valid: [AudiobookModel] = []
            var toDelete: [AudiobookModel] = []
            for book in fetched {
                if validateAudiobookFile(book) { valid.append(book) } else { toDelete.append(book) }
            }
            self.audiobooks = valid
            self.isLoadingLibrary = false
            self.processPendingImports()
            if !toDelete.isEmpty {
                Task.detached(priority: .utility) {
                    let background = self.swiftDataController.backgroundContext()
                    for b in toDelete { background.delete(b) }
                    do { try background.save() } catch {
                        print("❌ AudiobookManager: Failed to save after cleanup: \(error)")
                    }
                }
            }
        } catch {
            print("❌ AudiobookManager: Failed to fetch audiobooks: \(error)")
            self.isLoadingLibrary = false
        }
    }
    
    private func validateAudiobookFile(_ audiobook: AudiobookModel) -> Bool {
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
    func handleImportRequest(urls: [URL], completion: (() -> Void)? = nil) {
        // If library is still loading, queue the import operation
        if isLoadingLibrary {
            print("📚 AudiobookManager: Library still loading, queueing import operation")
            pendingImports.append((urls: urls, completion: completion))
            return
        }
        
        // Process immediately if library is loaded
        processImport(urls: urls, completion: completion)
    }
    
    private func processImport(urls: [URL], completion: (() -> Void)? = nil) {
        for url in urls {
            Task {
                print("📂 Processing import: \(url.lastPathComponent)")
                
                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                
                // Check if it's a ZIP file
                if url.pathExtension.lowercased() == "zip" {
                    print("📦 Importing ZIP file: \(url.lastPathComponent)")
                    await self.importZIPAudiobook(from: url)
                } else {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            print("📁 Importing folder: \(url.lastPathComponent)")
                            await self.importAudiobookFolder(from: url)
                        } else {
                            print("🎵 Importing single file: \(url.lastPathComponent)")
                            await self.importAudiobook(from: url)
                        }
                    } else {
                        print("🎵 Importing file (fallback): \(url.lastPathComponent)")
                        await self.importAudiobook(from: url)
                    }
                }
            }
        }
        
        // Call completion handler if provided
        completion?()
    }
    
    private func processPendingImports() {
        guard !pendingImports.isEmpty else { return }
        
        print("📚 AudiobookManager: Processing \(pendingImports.count) pending import(s)")
        
        let imports = pendingImports
        pendingImports.removeAll()
        
        for i in imports {
            processImport(urls: i.urls, completion: i.completion)
        }
    }
    
    func importZIPAudiobook(from zipURL: URL) async {
        await MainActor.run {
            isImporting = true
        }
        
        print("📦 AudiobookManager: Starting ZIP audiobook import from: \(zipURL.lastPathComponent)")
        
        // Extract and validate ZIP content
        guard let extractedFolderURL = await ZIPImporter.importZIPFile(from: zipURL) else {
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
        // Import the extracted folder using existing folder import logic
        await importAudiobookFolder(from: extractedFolderURL)
        
        // Clean up temporary extraction directory
        let tempDirectory = extractedFolderURL.deletingLastPathComponent().deletingLastPathComponent()
        ZIPImporter.cleanupDirectory(at: tempDirectory)
        
        print("✅ AudiobookManager: ZIP audiobook import completed")
    }
    
    func importAudiobookFolder(from folderURL: URL) async {
        await MainActor.run {
            isImporting = true
        }
        
        print("📁 AudiobookManager: Starting folder import from: \(folderURL.lastPathComponent)")
        
        guard let folderAudiobook = await FolderImporter.importAudiobookFolder(from: folderURL) else {
            print("🔍 AudiobookManager: Folder import failed, checking for single audio file with CUE")
            
            // Check if this folder contains a CUE file with a single audio file
            let cueFiles = CUEParser.findCUEFiles(in: folderURL)
            if let firstCueFile = cueFiles.first,
               let parsedCue = CUEParser.parseCUEFile(at: firstCueFile),
               let audioFile = CUEParser.matchCUEWithAudioFile(cueFile: parsedCue, in: folderURL) {
                
                print("🎵 AudiobookManager: Found CUE + audio file, importing as single file audiobook")
                print("   CUE file: \(firstCueFile.lastPathComponent)")
                print("   Audio file: \(audioFile.lastPathComponent)")
                
                // Import as single file but use CUE metadata for chapters
                await importCUEBasedAudiobook(audioFile: audioFile, cueFile: parsedCue)
                return
            }
            
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
            let context = swiftDataController.context
            let audiobook = AudiobookModel()
            
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
                let chapter = ChapterModel(
                    title: folderChapter.title,
                    chapterNumber: Int16(folderChapter.chapterNumber),
                    startTime: folderChapter.startTimeInBook,
                    endTime: folderChapter.startTimeInBook + folderChapter.duration
                )
                chapter.audiobook = audiobook
                context.insert(chapter)
            }
            
            // Insert the audiobook into the context
            context.insert(audiobook)
            
            print("✅ AudiobookManager: Created multi-file audiobook record:")
            print("   Title: \(folderAudiobook.title)")
            print("   Author: \(folderAudiobook.author ?? "Unknown")")
            print("   Duration: \(formatTime(folderAudiobook.totalDuration))")
            print("   Chapters: \(folderAudiobook.chapters.count)")
            print("   Folder Path: \(localFolderURL.path)")
            
            swiftDataController.save()
            fetchAudiobooks()
            isImporting = false
        }
    }

    
    // MARK: - CUE-based Audiobook Import
    
    private func importCUEBasedAudiobook(audioFile: URL, cueFile: CUEFile) async {
        print("🎵 AudiobookManager: Starting CUE-based audiobook import")
        
        // Extract metadata from the audio file
        guard let metadata = await MetadataExtractor.extractMetadata(from: audioFile) else {
            print("❌ AudiobookManager: Failed to extract metadata from audio file")
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
        // Copy the single audio file to documents directory
        guard let localURL = await copyFileToDocuments(from: audioFile) else {
            await MainActor.run {
                isImporting = false
            }
            return
        }
        
        // Create audiobook entity (single file, not folder)
        await MainActor.run {
            let context = swiftDataController.context
            let audiobook = AudiobookModel()
            
            audiobook.id = UUID()
            // Use CUE metadata where available, fallback to audio metadata
            audiobook.title = cueFile.title ?? metadata.title
            audiobook.author = cueFile.performer ?? metadata.author
            audiobook.narrator = metadata.narrator
            audiobook.duration = metadata.duration
            audiobook.fileURL = localURL.path // Single file path
            audiobook.dateAdded = Date()
            audiobook.currentPosition = 0
            audiobook.isFinished = false
            
            if let coverImage = metadata.coverImage {
                audiobook.coverImageData = coverImage.jpegData(compressionQuality: 0.8)
            } else {
                audiobookNeedingCover = audiobook
            }
            
            // Add chapters from CUE file
            for (index, track) in cueFile.tracks.enumerated() {
                // Calculate end time (next track start or total duration)
                let endTime = (index + 1 < cueFile.tracks.count) ? 
                    cueFile.tracks[index + 1].startTime : metadata.duration
                let chapter = ChapterModel(
                    title: track.title,
                    chapterNumber: Int16(track.number),
                    startTime: track.startTime,
                    endTime: endTime
                )
                chapter.audiobook = audiobook
                context.insert(chapter)
            }
            
            // Insert the audiobook into the context
            context.insert(audiobook)
            
            print("✅ AudiobookManager: Created CUE-based audiobook record:")
            print("   Title: \(audiobook.title ?? "Unknown")")
            print("   Author: \(audiobook.author ?? "Unknown")")
            print("   Duration: \(formatTime(metadata.duration))")
            print("   Chapters: \(cueFile.tracks.count) (from CUE)")
            print("   File Path: \(localURL.path)")
            
            swiftDataController.save()
            fetchAudiobooks()
            isImporting = false
        }
    }
    
    func importAudiobook(from url: URL) async {
        await MainActor.run {
            isImporting = true
        }
        
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
            await MainActor.run {
                isImporting = false
            }
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
        await MainActor.run {
            let context = swiftDataController.context
            let audiobook = AudiobookModel()
            
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
                let chapter = ChapterModel(
                    title: chapterInfo.title,
                    chapterNumber: Int16(chapterInfo.chapterNumber),
                    startTime: chapterInfo.startTime,
                    endTime: chapterInfo.endTime
                )
                chapter.audiobook = audiobook
                context.insert(chapter)
            }
            
            // Insert the audiobook into the context
            context.insert(audiobook)
            
            swiftDataController.save()
            fetchAudiobooks()
            isImporting = false
        }
    }
    
    // MARK: - Cover Image Management
    @MainActor
    func updateCoverImage(for audiobook: AudiobookModel, with image: UIImage) {
        audiobook.coverImageData = image.jpegData(compressionQuality: 0.8)
        swiftDataController.save()
        fetchAudiobooks()
        
        // Clear the needing cover flag if this was the audiobook that needed it
        if audiobookNeedingCover?.persistentModelID == audiobook.persistentModelID {
            audiobookNeedingCover = nil
        }
    }
    
    private func copyFileToDocuments(from sourceURL: URL) async -> URL? {
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
            
            for folderChapter in folderAudiobook.chapters {
                let sourceFileURL = sourceFolderURL.appendingPathComponent(folderChapter.fileName)
                let destinationFileURL = destinationFolderURL.appendingPathComponent(folderChapter.fileName)
                
                // Check if source file exists
                guard fileManager.fileExists(atPath: sourceFileURL.path) else {
                    print("⚠️ AudiobookManager: Source file not found: \(folderChapter.fileName)")
                    continue
                }
                
                // If destination file already exists, remove it first
                if fileManager.fileExists(atPath: destinationFileURL.path) {
                    try fileManager.removeItem(at: destinationFileURL)
                }
                
                try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
                totalCopiedSize += folderChapter.fileSize
                copiedFiles += 1
                
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
    
    // MARK: - Progress Management (duplicate removed - the real implementation is earlier)
    
    // MARK: - Bookmark Management
    @MainActor
    func createBookmarkLegacy(for audiobook: AudiobookModel, at timestamp: TimeInterval, title: String, note: String? = nil) {
        // This is a duplicate - the real createBookmark using SwiftData is earlier in the file
        let context = swiftDataController.context
        let bookmark = BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
        bookmark.audiobook = audiobook
        context.insert(bookmark)
        
        swiftDataController.save()
    }
    
    // Legacy deleteBookmarkOld function removed - using SwiftData deleteBookmark instead
    
    // MARK: - Library Management
    @MainActor
    func deleteAudiobook(_ audiobook: AudiobookModel) {
        // Delete physical file
        if let filePath = audiobook.fileURL, !filePath.isEmpty {
            let fileURL = URL(fileURLWithPath: filePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from Core Data
        swiftDataController.context.delete(audiobook)
        swiftDataController.save()
        fetchAudiobooks()
    }
    
    @MainActor
    func renameAudiobook(_ audiobook: AudiobookModel, newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        audiobook.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        swiftDataController.save()
        fetchAudiobooks()
        
        print("✏️ AudiobookManager: Renamed audiobook to: \(newTitle)")
    }
    
    @MainActor
    func markAsRead(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
        audiobook.currentPosition = audiobook.duration // Set to end
        swiftDataController.save()
        fetchAudiobooks()
        
        print("✅ AudiobookManager: Marked audiobook as finished: \(audiobook.title ?? "Unknown")")
    }
    
    @MainActor
    func markAsUnread(_ audiobook: AudiobookModel) {
        audiobook.isFinished = false
        swiftDataController.save()
        fetchAudiobooks()
        
        print("🔄 AudiobookManager: Marked audiobook as unfinished: \(audiobook.title ?? "Unknown")")
    }
    
    func searchAudiobooks(query: String) -> [AudiobookModel] {
        guard !query.isEmpty else { return audiobooks }
        
        return audiobooks.filter { audiobook in
            let title = audiobook.title?.lowercased() ?? ""
            let author = audiobook.author?.lowercased() ?? ""
            let searchQuery = query.lowercased()
            
            return title.contains(searchQuery) || author.contains(searchQuery)
        }
    }
}
