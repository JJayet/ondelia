import Foundation
import SwiftData
import UIKit

// MARK: - Importing a folder of audio files
extension AudiobookManager {
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
            await reportImportFailure(error)
        }
    }
}
