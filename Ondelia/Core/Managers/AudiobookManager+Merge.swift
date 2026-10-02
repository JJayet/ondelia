import Foundation
import AVFoundation
import SwiftData
import UIKit

/// One source book on its way into a merged folder. Plain values, so the copying can leave the main actor.
private struct MergePart: Sendable {
    let sourceURL: URL
    let title: String
    let duration: TimeInterval
}

private struct MergedFolder: Sendable {
    let folderURL: URL
    let chapters: [FolderChapter]
    let totalDuration: TimeInterval
}

extension AudiobookManager {
    /// Whether `audiobook` can be folded into a merged book: single-file books only.
    // ponytail: a folder-backed book is skipped rather than flattened, because re-basing its
    // existing chapter times is the whole job. Add it if merging merged books is ever asked for.
    func canMerge(_ audiobook: AudiobookModel) -> Bool {
        guard let url = audiobook.resolvedFileURL else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    /// Folds several single-file audiobooks into one, each source becoming a chapter.
    ///
    /// The files are copied into the new folder first and the originals removed only once the
    /// merged book is saved, so a failure anywhere leaves the library exactly as it was.
    /// The listener's state carries over: bookmarks, position, Finished, Collections, Up Next.
    @MainActor
    @discardableResult
    func mergeAudiobooks(_ books: [AudiobookModel], title: String) async -> AudiobookModel? {
        let sources = books
            .filter { canMerge($0) }
            .sorted {
                ($0.resolvedFileURL?.lastPathComponent ?? "")
                    .localizedStandardCompare($1.resolvedFileURL?.lastPathComponent ?? "") == .orderedAscending
            }

        guard sources.count > 1 else {
            importErrorMessage = NSLocalizedString(
                "At least two single-file audiobooks are needed to merge.",
                comment: "Merge refused, not enough mergeable books"
            )
            return nil
        }

        let parts = sources.compactMap { book -> MergePart? in
            guard let url = book.resolvedFileURL else { return nil }
            return MergePart(
                sourceURL: url,
                title: book.title ?? url.deletingPathExtension().lastPathComponent,
                duration: book.duration
            )
        }
        let cover = sources.compactMap(\.coverImageData).first
        let author = sources.compactMap(\.author).first { $0 != "Unknown Author" }
        let narrator = sources.compactMap(\.narrator).first

        isImporting = true
        importQueueTotal = parts.count
        importQueueCompleted = 0
        currentImportFileName = title

        let merged: MergedFolder
        do {
            merged = try await assembleMergedFolder(named: title, from: parts, author: author, narrator: narrator)
        } catch {
            isImporting = false
            currentImportFileName = nil
            importErrorMessage = String(
                format: NSLocalizedString("The audiobooks could not be merged: %@", comment: "Merge failure"),
                error.localizedDescription
            )
            return nil
        }

        let context = swiftDataController.context
        // The same merge done on another device already synced its book here, folder missing:
        // this folder is that book's audio, so no second row.
        let synced = entryAwaitingFolder(at: merged.folderURL, duration: merged.totalDuration)
        // A synced merge already carries the state its own device carried over.
        let progress = Self.mergedProgress(of: sources, chapters: merged.chapters)
        let audiobook = synced ?? AudiobookModel(
            title: title,
            author: author ?? "Unknown Author",
            narrator: narrator,
            fileURL: AudiobookModel.storedPath(for: merged.folderURL),
            duration: merged.totalDuration,
            currentPosition: progress.position,
            // Every source Finished: so is the merge, with no new Finish in the log.
            isFinished: progress.finished,
            coverImageData: cover,
            dateAdded: Date(),
            lastPlayed: sources.map(\.lastPlayed).max() ?? .distantPast
        )
        if synced == nil {
            if progress.position > 0 { audiobook.positionUpdatedAt = Date() }
            context.insert(audiobook)
            for item in merged.chapters {
                let chapter = ChapterModel(
                    title: item.title,
                    chapterNumber: Int16(item.chapterNumber),
                    startTime: item.startTimeInBook,
                    endTime: item.startTimeInBook + item.duration
                )
                chapter.audiobook = audiobook
                context.insert(chapter)
            }
        }

        do {
            try context.save()
        } catch {
            // The originals are still untouched, so dropping the copy undoes the whole merge.
            try? FileManager.default.removeItem(at: merged.folderURL)
            if synced == nil { context.delete(audiobook) }
            isImporting = false
            currentImportFileName = nil
            importErrorMessage = String(
                format: NSLocalizedString("The audiobooks could not be merged: %@", comment: "Merge failure"),
                error.localizedDescription
            )
            return nil
        }

        // Only now that the merged book is on disk and saved are the sources safe to drop.
        // Playback writes progress into the model it holds, so it lets go of a source first.
        if let playing = GlobalAudioManager.shared.currentAudiobook, sources.contains(where: { $0.id == playing.id }) {
            GlobalAudioManager.shared.unload()
        }
        if synced == nil { moveBookmarks(from: sources, chapters: merged.chapters, onto: audiobook) }
        replaceInCollectionsAndQueue(sources, with: audiobook)
        for source in sources {
            if let url = source.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            context.delete(source)
        }
        swiftDataController.save()

        coverBatch.removeAll()
        isImporting = false
        currentImportFileName = nil
        importQueueCompleted = importQueueTotal
        fetchAudiobooks()

        Log.library.debug("📚 AudiobookManager: Merged \(sources.count) audiobooks into '\(title)'")
        return audiobook
    }

    /// Copies every part into a fresh folder under Audiobooks and writes the playback manifest.
    private nonisolated func assembleMergedFolder(
        named title: String,
        from parts: [MergePart],
        author: String?,
        narrator: String?
    ) async throws -> MergedFolder {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let audiobooksDirectory = documents.appendingPathComponent("Audiobooks")
        try fileManager.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)

        let baseName = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var folderURL = audiobooksDirectory.appendingPathComponent(baseName.isEmpty ? "Audiobook" : baseName)
        var counter = 1
        while fileManager.fileExists(atPath: folderURL.path) {
            folderURL = audiobooksDirectory.appendingPathComponent("\(baseName) (\(counter))")
            counter += 1
        }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        do {
            var chapters: [FolderChapter] = []
            var cumulative: TimeInterval = 0
            var usedNames = Set<String>()

            for (index, part) in parts.enumerated() {
                var fileName = part.sourceURL.lastPathComponent
                var suffix = 1
                while usedNames.contains(fileName) {
                    let stem = part.sourceURL.deletingPathExtension().lastPathComponent
                    fileName = "\(stem)_\(suffix).\(part.sourceURL.pathExtension)"
                    suffix += 1
                }
                usedNames.insert(fileName)

                let destination = try SafeImportPath.resolvedURL(for: fileName, inside: folderURL)
                try fileManager.copyItem(at: part.sourceURL, to: destination)

                // A book imported from a file with unreadable metadata can carry a zero duration;
                // the merged manifest has to be right or every later chapter starts in the wrong place.
                var duration = part.duration
                if duration <= 0 {
                    duration = (try? await AVURLAsset(url: destination).load(.duration).seconds) ?? 0
                    if !duration.isFinite { duration = 0 }
                }
                let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
                let fileSize = attributes?[.size] as? Int64 ?? 0

                chapters.append(FolderChapter(
                    title: part.title,
                    fileName: fileName,
                    duration: duration,
                    startTimeInBook: cumulative,
                    chapterNumber: index + 1,
                    fileSize: fileSize
                ))
                cumulative += duration
                await MainActor.run { self.importQueueCompleted = index + 1 }
            }

            let manifest = FolderAudiobook(
                title: title,
                author: author,
                narrator: narrator,
                totalDuration: cumulative,
                chapters: chapters,
                folderPath: folderURL.path,
                coverImage: nil
            )
            try createFolderManifest(folderAudiobook: manifest)
                .write(to: folderURL.appendingPathComponent("audiobook_manifest.json"))

            folderURL.disableFileProtection()
            return MergedFolder(folderURL: folderURL, chapters: chapters, totalDuration: cumulative)
        } catch {
            try? fileManager.removeItem(at: folderURL)
            throw error
        }
    }
}
