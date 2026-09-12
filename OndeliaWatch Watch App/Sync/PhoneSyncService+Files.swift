import Foundation
import SwiftData

/// Incoming files, the manifest that follows them, and the deletions that undo them.
extension PhoneSyncService {
    /// Runs inside `session(_:didReceive:)`, before it returns: WatchConnectivity deletes the
    /// staged file the moment the callback ends, so there is no hopping to the main actor first.
    nonisolated static func moveChapterFile(at source: URL, bookID: UUID, number: Int) -> Bool {
        let destination = WatchLibraryDisk.chapterURL(bookID: bookID, number: number)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: source, to: destination)
            return true
        } catch {
            Log.sync.error("❌ PhoneSyncService: chapter move failed: \(error.localizedDescription)")
            return false
        }
    }

    func applyCover(_ data: Data, to bookID: UUID) {
        // Kept on disk as well: the file can arrive before the snapshot that creates the row,
        // and the phone only ever sends a given cover once.
        WatchLibraryDisk.writeCover(data, bookID: bookID)
        guard let book = book(bookID) else { return }
        book.coverImageData = data
        WatchLibraryStore.save()
    }

    /// A chapter landed: refresh the timeline, tell the phone what we now hold, and let the
    /// player carry on if it was stopped waiting for exactly this file.
    func didLandChapter(bookID: UUID, number: Int) {
        rewriteManifest(bookID: bookID)
        WatchTransferState.shared.refresh(bookID: bookID)
        sendInventory(bookID: bookID)
        Log.sync.debug("✅ PhoneSyncService: chapter \(number, privacy: .public) landed")
        Task { await WatchAudioManager.shared.chapterArrived(bookID: bookID, number: number) }
    }

    /// The manifest always lists every chapter the store knows about, present or not — that is
    /// what keeps a partially-sent book's timeline honest.
    func rewriteManifest(bookID: UUID) {
        guard let book = book(bookID) else { return }
        WatchLibraryDisk.writeManifest(bookID: bookID, chapters: chapterSummaries(of: book))
    }

    func chapterSummaries(of book: AudiobookModel) -> [ChapterSummary] {
        book.sortedChapters.map {
            ChapterSummary(number: Int($0.chapterNumber), title: $0.title, start: $0.startTime, end: $0.endTime)
        }
    }

    func book(_ bookID: UUID) -> AudiobookModel? {
        let descriptor = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == bookID })
        return try? WatchLibraryStore.shared.context.fetch(descriptor).first
    }

    // MARK: - Deleting

    func deleteChapter(bookID: UUID, number: Int) {
        WatchLibraryDisk.deleteChapter(bookID: bookID, number: number)
        rewriteManifest(bookID: bookID)
        WatchTransferState.shared.refresh(bookID: bookID)
        send(SyncEvent.chapterDeleted(bookID: bookID, chapterNumber: number))
        sendInventory(bookID: bookID)
    }

    /// The phone dropped this book: throw away the audio but keep the row, which the next
    /// snapshot will either refresh or remove.
    func clearBook(_ bookID: UUID) {
        WatchLibraryDisk.deleteBook(bookID)
        WatchTransferState.shared.forget(bookID: bookID)
        WatchAudioManager.shared.unloadIfPlaying(bookID: bookID)
        sendInventory(bookID: bookID)
    }

    func clearAll() {
        let known = WatchLibraryDisk.bookIDsWithContent()
        WatchAudioManager.shared.stop()
        WatchLibraryDisk.deleteEverything()
        WatchTransferState.shared.forgetEverything()
        for bookID in known { sendInventory(bookID: bookID) }
    }
}
