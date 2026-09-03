import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    // MARK: - Import Operations
    /// Queues an import, and runs it when the library is ready and no other import is in flight.
    ///
    /// One at a time is not a nicety. `importBatch`, `coverBatch`, `pendingMergeTitle` and the
    /// progress counters all describe *the* running import, so a second run starting mid-flight
    /// resets them under the first — which is exactly how the merge offer went missing: whichever
    /// run finished second found `pendingMergeTitle` already consumed and silently offered nothing.
    @MainActor
    func handleImportRequest(urls: [URL], completion: (@Sendable () -> Void)? = nil) {
        guard swiftDataController.isLoaded, !isLoadingLibrary, !isImportRunning else {
            Log.library.debug("📚 AudiobookManager: Busy, queueing import of \(urls.count) item(s)")
            pendingImports.append((urls: urls, completion: completion))
            drainPendingImportsWhenIdle()
            return
        }

        isImportRunning = true
        importQueueTotal = urls.count
        importQueueCompleted = 0
        isImporting = true
        processImport(unsortedURLs: urls, completion: completion)
    }

    @MainActor
    private func drainPendingImportsWhenIdle() {
        guard !isDrainingImports else { return }
        isDrainingImports = true
        Task { @MainActor in
            while !self.swiftDataController.isLoaded || self.isLoadingLibrary || self.isImportRunning {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            self.isDrainingImports = false
            self.processPendingImports()
        }
    }

    private nonisolated func processImport(unsortedURLs: [URL], completion: (@Sendable () -> Void)? = nil) {
        // Neither the document picker nor a directory listing promises an order, and import order
        // is the only record of it: titles come from file metadata and say nothing about sequence.
        let urls = unsortedURLs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let manager = self
        Task.detached(priority: .userInitiated) {
            // Picking every file of a folder is the same ambiguity as picking the folder itself,
            // so both end up offering the same merge once the files are safely in the library.
            let isMultiFilePick = manager.isMultiFileAudioPick(urls)
            let folderName = manager.commonAudioFolder(of: urls)?.lastPathComponent
            await MainActor.run {
                manager.importBatch.removeAll()
                manager.coverBatch.removeAll()
                // Often nil: see `commonAudioFolder`. `importAudiobook` fills it from the album tag.
                manager.pendingMergeTitle = folderName
            }

            for url in urls {
                Log.library.debug("📂 Processing import: \(url.lastPathComponent)")
                await MainActor.run { manager.currentImportFileName = url.lastPathComponent }

                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                if url.pathExtension.lowercased() == "zip" {
                    Log.library.debug("📦 Importing ZIP file: \(url.lastPathComponent)")
                    await manager.importZIPAudiobook(from: url)
                } else {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        Log.library.debug("📁 Importing folder: \(url.lastPathComponent)")
                        await manager.importAudiobookFolder(from: url)
                    } else {
                        Log.library.debug("🎵 Importing single file: \(url.lastPathComponent)")
                        // A multi-file pick shares one cover question, and one merge offer, at the end.
                        await manager.importAudiobook(from: url, inCoverBatch: isMultiFilePick)
                    }
                }

                await MainActor.run {
                    manager.importQueueCompleted += 1
                }
            }
            // A merge is offered for one source: a lone folder or archive, or a pick of several
            // audio files. A mixed pick of files and folders has no single answer worth suggesting.
            await manager.finishImportBatch(offerMerge: isMultiFilePick || urls.count == 1)
            completion?()
        }
    }

    @MainActor
    func processPendingImports() {
        guard !pendingImports.isEmpty, !isImportRunning else { return }

        Log.library.debug("📚 AudiobookManager: \(self.pendingImports.count) import(s) queued, starting the next")
        let next = pendingImports.removeFirst()
        handleImportRequest(urls: next.urls, completion: next.completion)
    }

    nonisolated func importZIPAudiobook(from zipURL: URL) async {
        await MainActor.run { isImporting = true }

        Log.library.debug("📦 AudiobookManager: Starting ZIP audiobook import from: \(zipURL.lastPathComponent)")

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

        Log.library.debug("✅ AudiobookManager: ZIP audiobook import completed")
    }

    // MARK: - Import Batch

    /// Whether a pick is several audio files, which on its own is reason to ask whether they
    /// are one book split into chapters.
    ///
    /// Deliberately not "several files that share a folder". A file provider — iCloud Drive,
    /// Drive, Dropbox, a NAS — stages every picked file in its own numbered container:
    ///
    ///     File Provider Storage/f104399954361/101 - Opening Credits.mp3
    ///     File Provider Storage/f104399970043/102 - Epigrah (I).mp3
    ///
    /// so eight files picked out of one folder arrive with eight different parents and nothing
    /// shared to key off. The act of picking several audio files at once is the signal.
    ///
    /// Non-audio strays are ignored rather than disqualifying the pick: a `cover.jpg` says
    /// nothing about whether the audio is one book or several.
    nonisolated func isMultiFileAudioPick(_ urls: [URL]) -> Bool {
        let audioFiles = urls.filter { !$0.hasDirectoryPath && FolderImporter.isAudioFile($0) }
        return audioFiles.count > 1 && !urls.contains(where: { $0.hasDirectoryPath })
    }

    /// The folder a selection came from, when they really do share one — true for local files,
    /// false for anything a file provider staged. Only used to suggest a name.
    ///
    /// Judged from the URLs alone. Picked files can live outside the sandbox, where nothing is
    /// readable, not even `fileExists`, until their security scope is claimed.
    nonisolated func commonAudioFolder(of urls: [URL]) -> URL? {
        guard isMultiFileAudioPick(urls) else { return nil }
        let audioFiles = urls.filter { !$0.hasDirectoryPath && FolderImporter.isAudioFile($0) }
        let folders = Set(audioFiles.map { $0.deletingLastPathComponent().standardizedFileURL })
        guard folders.count == 1, let folder = folders.first else { return nil }
        return folder
    }

    /// True when the folder already declares how it is meant to be read, leaving nothing to ask.
    nonisolated func hasStructuredLayout(_ folderURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("complete.json").path)
            || !CUEParser.findCUEFiles(in: folderURL).isEmpty
    }

    /// Closes out an import: the books are already saved, so this only decides which single
    /// follow-up question, if any, is worth asking.
    @MainActor
    func finishImportBatch(offerMerge: Bool = true) {
        isImporting = false
        currentImportFileName = nil
        importQueueCompleted = importQueueTotal

        let count = importBatch.count
        // Last resort when neither a shared folder nor an album tag gave a name: the first book's
        // own title. A poor guess is still better than dropping the offer, and it can be renamed.
        let suggestedTitle = pendingMergeTitle ?? importBatch.first?.title
        pendingMergeTitle = nil

        Log.library.debug("📚 AudiobookManager: Import finished — \(count) book(s), merge title \(suggestedTitle ?? "none"), offer \(offerMerge)")
        guard offerMerge, count > 1, let suggestedTitle else {
            importBatch.removeAll()
            resolveBatchCover()
            finishImportRun()
            return
        }
        // The batch stays on the manager rather than being captured: SwiftData models are not
        // Sendable, so it must never cross into the answering task.
        mergePrompt = MergePrompt(suggestedTitle: suggestedTitle, bookCount: count) { [weak self] merge in
            // Clearing the prompt first keeps a second answer (button plus dismissal) from acting twice.
            guard let self, self.mergePrompt != nil else { return }
            self.mergePrompt = nil
            guard merge else {
                self.importBatch.removeAll()
                self.resolveBatchCover()
                self.finishImportRun()
                return
            }
            Task { @MainActor in
                let batch = self.importBatch
                self.importBatch.removeAll()
                await self.mergeAudiobooks(batch, title: suggestedTitle)
                self.finishImportRun()
            }
        }
    }

    /// Releases the import gate. Held past the end of the copying on purpose: the batch is still
    /// needed while the merge offer is on screen, so the next import waits for the answer.
    @MainActor
    func finishImportRun() {
        isImportRunning = false
        processPendingImports()
    }

    /// Asks for one cover for the whole batch, and only when none of the books found their own.
    @MainActor
    func resolveBatchCover() {
        defer { coverBatch.removeAll() }
        guard let first = coverBatch.first, coverBatch.allSatisfy({ $0.coverImageData == nil }) else { return }
        audiobookNeedingCover = first
    }

    /// Imports every file as its own audiobook, sharing the folder cover and asking for one only at the end.
    private nonisolated func importFilesAsSeparateAudiobooks(_ audioFiles: [URL], from folderURL: URL) async {
        Log.library.debug("📚 AudiobookManager: Importing \(audioFiles.count) files as separate audiobooks")
        let folderCover = await FolderImporter.findCoverImage(in: folderURL)

        await MainActor.run {
            // The folder counted as a single queue entry; it is really one entry per file.
            importQueueTotal += audioFiles.count - 1
            pendingMergeTitle = folderURL.lastPathComponent
        }

        for (index, audioFile) in audioFiles.enumerated() {
            await MainActor.run { currentImportFileName = audioFile.lastPathComponent }
            await importAudiobook(from: audioFile, fallbackCover: folderCover, inCoverBatch: true)
            // The caller credits the folder itself as one completed entry, so the last file is left to it.
            if index < audioFiles.count - 1 {
                await MainActor.run { importQueueCompleted += 1 }
            }
        }
    }

    nonisolated func importAudiobookFolder(from folderURL: URL) async {
        await MainActor.run {
            isImporting = true
        }

        Log.library.debug("📁 AudiobookManager: Starting folder import from: \(folderURL.lastPathComponent)")

        // A folder of loose audio files is ambiguous: it can be one book split into chapters,
        // or several separate books. Import them separately — that is the reversible answer —
        // and offer the merge afterwards, once nothing can be lost by ignoring the question.
        let audioFiles = FolderImporter.audioFiles(in: folderURL)
        if audioFiles.count > 1, !hasStructuredLayout(folderURL) {
            await importFilesAsSeparateAudiobooks(audioFiles, from: folderURL)
            return
        }

        guard let folderAudiobook = await FolderImporter.importAudiobookFolder(from: folderURL) else {
            Log.library.debug("🔍 AudiobookManager: Folder import failed, checking for single audio file with CUE")

            // Check if this folder contains a CUE file with a single audio file
            let cueFiles = CUEParser.findCUEFiles(in: folderURL)
            if let firstCueFile = cueFiles.first,
               let parsedCue = CUEParser.parseCUEFile(at: firstCueFile),
               let audioFile = CUEParser.matchCUEWithAudioFile(cueFile: parsedCue, in: folderURL) {

                Log.library.debug("🎵 AudiobookManager: Found CUE + audio file, importing as single file audiobook")
                Log.library.debug("   CUE file: \(firstCueFile.lastPathComponent)")
                Log.library.debug("   Audio file: \(audioFile.lastPathComponent)")

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
    private nonisolated func copyAndPersist(_ folderAudiobook: FolderAudiobook, sourceFolderURL: URL) async {
        guard let localFolderURL = await copyFolderToDocuments(
            from: sourceFolderURL,
            folderAudiobook: folderAudiobook
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
                    fileURL: AudiobookModel.storedPath(for: localFolderURL),
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
                importBatch.append(audiobook)
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
