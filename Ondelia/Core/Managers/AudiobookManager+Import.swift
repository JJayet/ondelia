import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    typealias ImportedHandler = @MainActor ([AudiobookModel]) -> Void

    // MARK: - Import Operations
    /// Queues an import, and runs it when the library is ready and no other import is in flight.
    ///
    /// One at a time is not a nicety. `importBatch`, `pendingMergeTitle` and the
    /// progress counters all describe *the* running import, so a second run starting mid-flight
    /// resets them under the first — which is exactly how the merge offer went missing: whichever
    /// run finished second found `pendingMergeTitle` already consumed and silently offered nothing.
    ///
    /// `onImported` receives the books the import ended with — after a merge, the merged one —
    /// including books it skipped because the library already held them.
    /// - Parameter mergesWithoutAsking: the import is one book, as a server download is: its
    ///   parts are merged without offering to.
    @MainActor
    func handleImportRequest(
        urls: [URL],
        mergesWithoutAsking: Bool = false,
        completion: (@Sendable () -> Void)? = nil,
        onImported: ImportedHandler? = nil
    ) {
        guard swiftDataController.isLoaded, !isLoadingLibrary, !isImportRunning else {
            Log.library.debug("📚 AudiobookManager: Busy, queueing import of \(urls.count) item(s)")
            pendingImports.append((
                urls: urls, mergesWithoutAsking: mergesWithoutAsking, completion: completion, onImported: onImported
            ))
            drainPendingImportsWhenIdle()
            return
        }

        isImportRunning = true
        self.onImported = onImported
        self.mergesWithoutAsking = mergesWithoutAsking
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
            await waitUntil {
                self.swiftDataController.isLoaded && !self.isLoadingLibrary && !self.isImportRunning
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
                        await manager.importAudiobook(from: url)
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
        handleImportRequest(
            urls: next.urls,
            mergesWithoutAsking: next.mergesWithoutAsking,
            completion: next.completion,
            onImported: next.onImported
        )
    }

    nonisolated func importZIPAudiobook(from zipURL: URL) async {
        await MainActor.run { isImporting = true }

        Log.library.debug("📦 AudiobookManager: Starting ZIP audiobook import from: \(zipURL.lastPathComponent)")

        // Extract and validate ZIP content
        guard let extracted = ZIPImporter.importZIPFile(from: zipURL) else {
            // Said out loud: the import otherwise ends with no book and no word why.
            let name = zipURL.deletingPathExtension().lastPathComponent
            await MainActor.run {
                importErrorMessage = String(
                    format: NSLocalizedString(
                        "\"%@\" contains no audio that can be imported.",
                        comment: "ZIP import failure: the archive has no usable audio, %@ is its name"
                    ),
                    name
                )
            }
            return
        }

        // Import the extracted folder using existing folder import logic
        await importAudiobookFolder(from: extracted.folder)
        // Audio at the archive's root sits in the extraction folder, named by a UUID: the
        // archive's own name is the one to suggest for the merge.
        if extracted.folder == extracted.root {
            let name = zipURL.deletingPathExtension().lastPathComponent
            await MainActor.run { pendingMergeTitle = name }
        }

        // Delete the extraction root itself. Walking two parents up from the audiobook folder
        // landed on the app's whole temporary directory whenever the archive held its audio at
        // the root, because the folder returned then *is* the extraction root.
        ZIPImporter.cleanupDirectory(at: extracted.root)

        Log.library.debug("✅ AudiobookManager: ZIP audiobook import completed")
    }
}
