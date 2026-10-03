import Foundation
import AVFoundation
import SwiftData
import UIKit

/// One source book on its way into a merged folder. Plain values, so the copying can leave the main actor.
private struct MergePart: Sendable {
    let sourceURL: URL
    let title: String
    let duration: TimeInterval

    init?(_ book: AudiobookModel) {
        guard let url = book.resolvedFileURL else { return nil }
        sourceURL = url
        title = book.title ?? url.deletingPathExtension().lastPathComponent
        duration = book.duration
    }
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
        let sources = mergeableSources(books)
        guard sources.count > 1 else {
            importErrorMessage = NSLocalizedString(
                "At least two single-file audiobooks are needed to merge.",
                comment: "Merge refused, not enough mergeable books"
            )
            return nil
        }

        let parts = sources.compactMap { MergePart($0) }
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
            failMerge(error)
            return nil
        }

        // The same merge done on another device already synced its book here, folder missing:
        // this folder is that book's audio, so no second row.
        let synced = entryAwaitingFolder(at: merged.folderURL, duration: merged.totalDuration)
        let audiobook = synced ?? insertMergedBook(
            title: title, author: author, narrator: narrator, sources: sources, merged: merged
        )

        do {
            try swiftDataController.context.save()
        } catch {
            // The originals are still untouched, so dropping the copy undoes the whole merge.
            try? FileManager.default.removeItem(at: merged.folderURL)
            if synced == nil { swiftDataController.context.delete(audiobook) }
            failMerge(error)
            return nil
        }

        // A synced merge already carries the state its own device carried over.
        replaceSources(sources, with: audiobook, chapters: merged.chapters, carryBookmarks: synced == nil)
        Log.library.debug("📚 AudiobookManager: Merged \(sources.count) audiobooks into '\(title)'")
        return audiobook
    }

    /// The books that can be merged, in file name order: the order their chapters take.
    private func mergeableSources(_ books: [AudiobookModel]) -> [AudiobookModel] {
        books
            .filter { canMerge($0) }
            .sorted {
                ($0.resolvedFileURL?.lastPathComponent ?? "")
                    .localizedStandardCompare($1.resolvedFileURL?.lastPathComponent ?? "") == .orderedAscending
            }
    }

    @MainActor
    private func failMerge(_ error: any Error) {
        isImporting = false
        currentImportFileName = nil
        importErrorMessage = String(
            format: NSLocalizedString("The audiobooks could not be merged: %@", comment: "Merge failure"),
            error.localizedDescription
        )
    }

    /// A new library row for `merged`, with its chapters and the sources' progress carried over.
    @MainActor
    private func insertMergedBook(
        title: String,
        author: String?,
        narrator: String?,
        sources: [AudiobookModel],
        merged: MergedFolder
    ) -> AudiobookModel {
        let context = swiftDataController.context
        let progress = Self.mergedProgress(of: sources, chapters: merged.chapters)
        let audiobook = AudiobookModel(
            title: title,
            author: author ?? "Unknown Author",
            narrator: narrator,
            fileURL: AudiobookModel.storedPath(for: merged.folderURL),
            duration: merged.totalDuration,
            currentPosition: progress.position,
            // Every source Finished: so is the merge, with no new Finish in the log.
            isFinished: progress.finished,
            coverImageData: sources.compactMap(\.coverImageData).first,
            dateAdded: Date(),
            lastPlayed: sources.map(\.lastPlayed).max() ?? .distantPast
        )
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
        return audiobook
    }

    /// Only once the merged book is on disk and saved are the sources safe to drop.
    @MainActor
    private func replaceSources(
        _ sources: [AudiobookModel],
        with audiobook: AudiobookModel,
        chapters: [FolderChapter],
        carryBookmarks: Bool
    ) {
        // Playback writes progress into the model it holds, so it lets go of a source first.
        if let playing = GlobalAudioManager.shared.currentAudiobook, sources.contains(where: { $0.id == playing.id }) {
            GlobalAudioManager.shared.unload()
        }
        if carryBookmarks { moveBookmarks(from: sources, chapters: chapters, onto: audiobook) }
        replaceInCollectionsAndQueue(sources, with: audiobook)
        for source in sources {
            if let url = source.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            swiftDataController.context.delete(source)
        }
        swiftDataController.save()

        isImporting = false
        currentImportFileName = nil
        importQueueCompleted = importQueueTotal
        fetchAudiobooks()
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
        let folderURL = Self.unusedFolderURL(for: title, in: audiobooksDirectory)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        do {
            var chapters: [FolderChapter] = []
            var cumulative: TimeInterval = 0
            var usedNames = Set<String>()

            for (index, part) in parts.enumerated() {
                let chapter = try await Self.copy(
                    part, asChapter: index + 1, startingAt: cumulative, into: folderURL, usedNames: &usedNames
                )
                chapters.append(chapter)
                cumulative += chapter.duration
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

    /// A folder in `directory` named after `title`, numbered when that name is taken.
    private nonisolated static func unusedFolderURL(for title: String, in directory: URL) -> URL {
        let baseName = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var folderURL = directory.appendingPathComponent(baseName.isEmpty ? "Audiobook" : baseName)
        var counter = 1
        while FileManager.default.fileExists(atPath: folderURL.path) {
            folderURL = directory.appendingPathComponent("\(baseName) (\(counter))")
            counter += 1
        }
        return folderURL
    }

    /// Copies one part into `folderURL`, under a file name no earlier part took.
    private nonisolated static func copy(
        _ part: MergePart,
        asChapter number: Int,
        startingAt start: TimeInterval,
        into folderURL: URL,
        usedNames: inout Set<String>
    ) async throws -> FolderChapter {
        var fileName = part.sourceURL.lastPathComponent
        var suffix = 1
        while usedNames.contains(fileName) {
            let stem = part.sourceURL.deletingPathExtension().lastPathComponent
            fileName = "\(stem)_\(suffix).\(part.sourceURL.pathExtension)"
            suffix += 1
        }
        usedNames.insert(fileName)

        let destination = try SafeImportPath.resolvedURL(for: fileName, inside: folderURL)
        try FileManager.default.copyItem(at: part.sourceURL, to: destination)

        // A book imported from a file with unreadable metadata can carry a zero duration;
        // the merged manifest has to be right or every later chapter starts in the wrong place.
        var duration = part.duration
        if duration <= 0 {
            duration = (try? await AVURLAsset(url: destination).load(.duration).seconds) ?? 0
            if !duration.isFinite { duration = 0 }
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0

        return FolderChapter(
            title: part.title,
            fileName: fileName,
            duration: duration,
            startTimeInBook: start,
            chapterNumber: number,
            fileSize: fileSize
        )
    }
}
