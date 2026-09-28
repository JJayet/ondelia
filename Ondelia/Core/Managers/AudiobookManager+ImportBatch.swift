import Foundation
import SwiftData
import UIKit

// MARK: - What one import run produced
//
// A run collects the books it created so the cover question and the merge offer are asked
// once for the batch rather than once per file.
extension AudiobookManager {
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
            let imported = importBatch
            importBatch.removeAll()
            coverBatch.removeAll()
            finishImportRun(matching: imported)
            return
        }
        // The batch stays on the manager rather than being captured: SwiftData models are not
        // Sendable, so it must never cross into the answering task.
        mergePrompt = MergePrompt(suggestedTitle: suggestedTitle, bookCount: count) { [weak self] merge in
            // Clearing the prompt first keeps a second answer (button plus dismissal) from acting twice.
            guard let self, self.mergePrompt != nil else { return }
            self.mergePrompt = nil
            guard merge else {
                let imported = self.importBatch
                self.importBatch.removeAll()
                self.coverBatch.removeAll()
                self.finishImportRun(matching: imported)
                return
            }
            Task { @MainActor in
                let batch = self.importBatch
                self.importBatch.removeAll()
                let merged = await self.mergeAudiobooks(batch, title: suggestedTitle)
                // Match the one book that came out of the merge, not the parts that went in.
                self.finishImportRun(matching: merged.map { [$0] } ?? batch)
            }
        }
    }

    /// Releases the import gate. Held past the end of the copying on purpose: the batch is still
    /// needed while the merge offer is on screen, so the next import waits for the answer.
    @MainActor
    func finishImportRun(matching imported: [AudiobookModel] = []) {
        isImportRunning = false
        onImported?(imported)
        onImported = nil
        // No-op unless Hardcover auto-match is switched on and a token is saved.
        Task { await HardcoverService.shared.autoMatch(imported) }
        processPendingImports()
    }

    /// Imports every file as its own audiobook, sharing the folder cover and asking for one only at the end.
}
