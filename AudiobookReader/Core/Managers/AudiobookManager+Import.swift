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
            
            // Early exit: mark progress handled by outer defer
            return
        }
        
        // Copy the entire folder to documents directory
        guard let localFolderURL = await copyFolderToDocuments(from: folderURL, folderAudiobook: folderAudiobook) else {
            // Early exit: mark progress handled by outer defer
            return
        }
        
        // Create audiobook entity with multiple files
        do {
            let bg = swiftDataController.backgroundContext()
            let audiobook = AudiobookModel(
                title: folderAudiobook.title,
                author: folderAudiobook.author ?? "Unknown Author",
                narrator: folderAudiobook.narrator,
                fileURL: localFolderURL.path,
                duration: folderAudiobook.totalDuration,
                currentPosition: 0,
                isFinished: false,
                coverImageData: nil,
                dateAdded: Date(),
                lastPlayed: Date.distantPast
            )
            if let coverImage = folderAudiobook.coverImage {
                audiobook.coverImageData = coverImage.jpegData(compressionQuality: 0.8)
            }
            for ch in folderAudiobook.chapters {
                let chapter = ChapterModel(
                    title: ch.title,
                    chapterNumber: Int16(ch.chapterNumber),
                    startTime: ch.startTimeInBook,
                    endTime: ch.startTimeInBook + ch.duration
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
