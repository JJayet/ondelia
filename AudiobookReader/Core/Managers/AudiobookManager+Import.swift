import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    // MARK: - Import Operations
    func handleImportRequest(urls: [URL], completion: (() -> Void)? = nil) {
        // If library or SwiftData are still loading, queue the import operation
        if isLoadingLibrary || !swiftDataController.isLoaded {
            print("📚 AudiobookManager: Library not ready, queueing import operation")
            pendingImports.append((urls: urls, completion: completion))
            // Kick a lightweight waiter to process once loaded
            Task { @MainActor in
                while (!self.swiftDataController.isLoaded) || self.isLoadingLibrary {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                self.processPendingImports()
            }
            return
        }
        
        // Process immediately if library is loaded
        importQueueTotal = urls.count
        importQueueCompleted = 0
        isImporting = true
        processImport(urls: urls, completion: completion)
    }
    
    private func processImport(urls: [URL], completion: (() -> Void)? = nil) {
        let manager = self
        Task.detached(priority: .userInitiated) {
            // Picking a folder's files is the same ambiguity as picking the folder itself, and the
            // document picker steers users towards the files, so ask here too.
            if let folderURL = await manager.commonAudioFolder(of: urls),
               await manager.askForSeparateBooks(folderURL, fileCount: urls.count) == false {
                await manager.importFilesAsOneAudiobook(urls, folderURL: folderURL)
                await MainActor.run {
                    manager.importQueueCompleted = manager.importQueueTotal
                    manager.isImporting = false
                    manager.currentImportFileName = nil
                }
                completion?()
                return
            }

            for url in urls {
                print("📂 Processing import: \(url.lastPathComponent)")
                await MainActor.run { manager.currentImportFileName = url.lastPathComponent }

                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                if url.pathExtension.lowercased() == "zip" {
                    print("📦 Importing ZIP file: \(url.lastPathComponent)")
                    await manager.importZIPAudiobook(from: url)
                } else {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        print("📁 Importing folder: \(url.lastPathComponent)")
                        await manager.importAudiobookFolder(from: url)
                    } else {
                        print("🎵 Importing single file: \(url.lastPathComponent)")
                        await manager.importAudiobook(from: url)
                    }
                }

                await MainActor.run {
                    manager.importQueueCompleted += 1
                    if manager.importQueueCompleted >= manager.importQueueTotal {
                        manager.isImporting = false
                        manager.currentImportFileName = nil
                    }
                }
            }
            completion?()
        }
    }
    
    func processPendingImports() {
        guard !pendingImports.isEmpty else { return }
        
        print("📚 AudiobookManager: Processing \(pendingImports.count) pending import(s)")
        
        let imports = pendingImports
        pendingImports.removeAll()
        
        for i in imports {
            processImport(urls: i.urls, completion: i.completion)
        }
    }
    
    func importZIPAudiobook(from zipURL: URL) async {
        await MainActor.run { isImporting = true }
        
        print("📦 AudiobookManager: Starting ZIP audiobook import from: \(zipURL.lastPathComponent)")
        
        // Extract and validate ZIP content
        guard let extractedFolderURL = await ZIPImporter.importZIPFile(from: zipURL) else {
            await MainActor.run { }
            return
        }
        
        // Import the extracted folder using existing folder import logic
        await importAudiobookFolder(from: extractedFolderURL)
        
        // Clean up temporary extraction directory
        let tempDirectory = extractedFolderURL.deletingLastPathComponent().deletingLastPathComponent()
        ZIPImporter.cleanupDirectory(at: tempDirectory)
        
        print("✅ AudiobookManager: ZIP audiobook import completed")
    }
    
    // MARK: - Folder Import Style

    /// The folder shared by a selection of two or more plain audio files, if there is one.
    /// Anything else (a single file, a ZIP, a folder, a mixed bag) is unambiguous and returns nil.
    func commonAudioFolder(of urls: [URL]) -> URL? {
        guard urls.count > 1 else { return nil }
        let audioExtensions = Set(FolderImporter.audioFileExtensions)
        var isDirectory: ObjCBool = false
        for url in urls {
            guard audioExtensions.contains(url.pathExtension.lowercased()),
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return nil }
        }
        let folders = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
        guard folders.count == 1, let folder = folders.first else { return nil }
        return folder
    }

    /// Merges a hand-picked selection into one audiobook, each file becoming a chapter.
    private func importFilesAsOneAudiobook(_ urls: [URL], folderURL: URL) async {
        let audioFiles = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        print("📚 AudiobookManager: Merging \(audioFiles.count) files into one audiobook")

        await MainActor.run {
            isImporting = true
            importQueueTotal = audioFiles.count
            importQueueCompleted = 0
            currentImportFileName = folderURL.lastPathComponent
        }

        // Only the picked files are readable, so hold their access across metadata reads and copying.
        let accessed = audioFiles.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }

        // Reading durations and copying bytes are both long over 80-odd files, so both report progress.
        guard let folderAudiobook = await FolderImporter.makeFolderAudiobook(
            from: audioFiles,
            folderURL: folderURL,
            onFileAnalyzed: { [weak self] index, fileName in
                Task { @MainActor in
                    self?.reportMergeProgress(
                        index,
                        fileName,
                        format: NSLocalizedString("Analyzing %@", comment: "Merge import progress, file being read")
                    )
                }
            }
        ) else {
            return
        }

        await MainActor.run { importQueueCompleted = 0 }
        let sourceFiles = Dictionary(audioFiles.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        await copyAndPersist(
            folderAudiobook,
            sourceFolderURL: folderURL,
            sourceFiles: sourceFiles,
            onFileCopied: { [weak self] index, fileName in
                self?.reportMergeProgress(
                    index,
                    fileName,
                    format: NSLocalizedString("Copying %@", comment: "Merge import progress, file being copied")
                )
            }
        )
    }

    @MainActor
    private func reportMergeProgress(_ index: Int, _ fileName: String, format: String) {
        currentImportFileName = String(format: format, fileName)
        importQueueCompleted = min(index, max(importQueueTotal - 1, 0))
    }

    /// True when the folder already declares how it is meant to be read, leaving nothing to ask.
    func hasStructuredLayout(_ folderURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("complete.json").path)
            || !CUEParser.findCUEFiles(in: folderURL).isEmpty
    }

    /// Suspends the import until the user picks an import style in `LibraryView`.
    func askForSeparateBooks(_ folderURL: URL, fileCount: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.folderImportPrompt = FolderImportPrompt(
                    folderName: folderURL.lastPathComponent,
                    fileCount: fileCount
                ) { [weak self] separateBooks in
                    // Clearing the prompt first keeps a second answer (button plus dismissal) from
                    // resuming the continuation twice.
                    guard let self, self.folderImportPrompt != nil else { return }
                    self.folderImportPrompt = nil
                    continuation.resume(returning: separateBooks)
                }
            }
        }
    }

    /// Imports every file as its own audiobook, sharing the folder cover and asking for one only at the end.
    private func importFilesAsSeparateAudiobooks(_ audioFiles: [URL], from folderURL: URL) async {
        print("📚 AudiobookManager: Importing \(audioFiles.count) files as separate audiobooks")
        let folderCover = await FolderImporter.findCoverImage(in: folderURL)

        await MainActor.run {
            coverBatch.removeAll()
            // The folder counted as a single queue entry; it is really one entry per file.
            importQueueTotal += audioFiles.count - 1
        }

        for (index, audioFile) in audioFiles.enumerated() {
            await MainActor.run { currentImportFileName = audioFile.lastPathComponent }
            await importAudiobook(from: audioFile, fallbackCover: folderCover, inCoverBatch: true)
            // The caller credits the folder itself as one completed entry, so the last file is left to it.
            if index < audioFiles.count - 1 {
                await MainActor.run { importQueueCompleted += 1 }
            }
        }

        await MainActor.run {
            if folderCover == nil, let first = coverBatch.first {
                audiobookNeedingCover = first
            } else {
                coverBatch.removeAll()
            }
        }
    }

    func importAudiobookFolder(from folderURL: URL) async {
        await MainActor.run {
            isImporting = true
        }
        
        print("📁 AudiobookManager: Starting folder import from: \(folderURL.lastPathComponent)")
        
        // A folder of loose audio files is ambiguous: it can be one book split into chapters,
        // or several separate books. Only the user knows, so ask.
        let audioFiles = FolderImporter.audioFiles(in: folderURL)
        if audioFiles.count > 1, !hasStructuredLayout(folderURL), await askForSeparateBooks(folderURL, fileCount: audioFiles.count) {
            await importFilesAsSeparateAudiobooks(audioFiles, from: folderURL)
            return
        }
        
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
            
            // Early exit: mark progress handled by outer defer
            return
        }
        
        await copyAndPersist(folderAudiobook, sourceFolderURL: folderURL)
    }

    /// Copies a folder audiobook into the library and stores it with its chapters.
    private func copyAndPersist(
        _ folderAudiobook: FolderAudiobook,
        sourceFolderURL: URL,
        sourceFiles: [String: URL]? = nil,
        onFileCopied: ((Int, String) -> Void)? = nil
    ) async {
        guard let localFolderURL = await copyFolderToDocuments(
            from: sourceFolderURL,
            folderAudiobook: folderAudiobook,
            sourceFiles: sourceFiles,
            onFileCopied: onFileCopied
        ) else {
            // Early exit: mark progress handled by outer defer
            return
        }
        
        // Persist on the main model context; clean up the copy if persistence fails.
        do {
            try await MainActor.run {
                let context = swiftDataController.context
                let audiobook = AudiobookModel(
                    title: folderAudiobook.title,
                    author: folderAudiobook.author ?? "Unknown Author",
                    narrator: folderAudiobook.narrator,
                    fileURL: localFolderURL.path,
                    duration: folderAudiobook.totalDuration,
                    currentPosition: 0,
                    isFinished: false,
                    coverImageData: folderAudiobook.coverImage?.jpegData(compressionQuality: 0.8),
                    dateAdded: Date(),
                    lastPlayed: Date.distantPast
                )
                context.insert(audiobook)
                for item in folderAudiobook.chapters {
                    let chapter = ChapterModel(
                        title: item.title,
                        chapterNumber: Int16(item.chapterNumber),
                        startTime: item.startTimeInBook,
                        endTime: item.startTimeInBook + item.duration
                    )
                    chapter.audiobook = audiobook
                    context.insert(chapter)
                }
                try context.save()
                fetchAudiobooks()
            }
        } catch {
            try? FileManager.default.removeItem(at: localFolderURL)
            await MainActor.run {
                importErrorMessage = String(
                    format: NSLocalizedString("The audiobook could not be saved: %@", comment: "Import persistence error"),
                    error.localizedDescription
                )
            }
        }
    }
}
