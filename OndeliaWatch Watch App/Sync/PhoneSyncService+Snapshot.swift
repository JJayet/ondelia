import Foundation
import SwiftData

/// Applying a `LibrarySnapshot` into the watch's own store.
extension PhoneSyncService {
    func applySnapshot(data: Data) {
        guard let snapshot = try? SyncCodec.decode(LibrarySnapshot.self, from: data) else {
            Log.sync.error("❌ PhoneSyncService: snapshot did not decode")
            return
        }
        apply(snapshot)
    }

    func apply(_ snapshot: LibrarySnapshot) {
        let context = WatchLibraryStore.shared.context
        let existing = (try? context.fetch(FetchDescriptor<AudiobookModel>())) ?? []
        var byID: [UUID: AudiobookModel] = [:]
        for book in existing { byID[book.id] = book }

        for summary in snapshot.books {
            upsert(summary, existing: byID[summary.id] ?? adoptTwin(of: summary), context: context)
            WatchServerAccount.shared.setLink(itemID: summary.serverItemID, for: summary.id)
        }

        // A book the phone no longer lists is only dropped when the watch holds no audio for
        // it; otherwise the listener would lose something they can still play offline. Nor
        // while it plays, or when it was played after the phone built this snapshot: a book
        // the watch streamed may not have reached the phone yet.
        let kept = Set(snapshot.books.map(\.id))
        for book in existing where !kept.contains(book.id) {
            guard WatchLibraryDisk.chaptersOnDisk(bookID: book.id).isEmpty,
                  WatchAudioManager.shared.currentBook?.id != book.id,
                  book.lastPlayed < snapshot.sentAt else { continue }
            WatchServerAccount.shared.setLink(itemID: nil, for: book.id)
            context.delete(book)
        }

        do { try context.save() } catch {
            Log.sync.error("❌ PhoneSyncService: snapshot save failed: \(error.localizedDescription)")
        }
        bookOrder = snapshot.books.map(\.id)
        phoneNowPlaying = snapshot.nowPlaying
        skipBackSeconds = snapshot.skipBackSeconds ?? 15
        skipForwardSeconds = snapshot.skipForwardSeconds ?? 15
        WatchAudioManager.shared.applyRemoteSkipIntervals()
    }

    /// A book this watch streamed first and the phone already held under another id: it takes
    /// the phone's id, so both sides speak of one book. The phone maps the old id for the
    /// events still on their way.
    private func adoptTwin(of summary: BookSummary) -> AudiobookModel? {
        guard let item = summary.serverItemID,
              let twin = WatchServerAccount.shared.book(forItem: item), twin.id != summary.id else { return nil }
        WatchServerAccount.shared.setLink(itemID: nil, for: twin.id)
        twin.id = summary.id
        return twin
    }

    private func upsert(_ summary: BookSummary, existing: AudiobookModel?, context: ModelContext) {
        let book: AudiobookModel
        if let existing {
            book = existing
        } else {
            book = AudiobookModel(id: summary.id)
            context.insert(book)
        }
        book.title = summary.title
        book.author = summary.author
        book.duration = summary.duration
        book.isFinished = summary.isFinished
        book.playbackSpeed = summary.playbackSpeed
        // The folder name is the book id, so `resolvedFileURL` points at the chapter folder.
        book.fileURL = summary.id.uuidString
        // A cover that landed before this row existed is waiting on disk for it.
        if book.coverImageData == nil { book.coverImageData = WatchLibraryDisk.cover(bookID: summary.id) }
        if WatchLibraryDisk.shouldApplyRemotePosition(remote: summary.positionUpdatedAt, local: book.positionUpdatedAt) {
            book.currentPosition = summary.currentPosition
            book.positionUpdatedAt = summary.positionUpdatedAt
        }
        replaceChapters(summary.chapters, on: book, context: context)
        upsertBookmarks(summary.bookmarks, on: book, context: context)
    }

    /// Chapters are replaced wholesale, but only when they actually differ: the application
    /// context arrives on every phone-side change and rewriting rows each time would churn the
    /// store for nothing.
    private func replaceChapters(_ incoming: [ChapterSummary], on book: AudiobookModel, context: ModelContext) {
        let wanted = incoming.sorted { $0.number < $1.number }
        let current = book.sortedChapters
        let unchanged = current.count == wanted.count && zip(current, wanted).allSatisfy { row, summary in
            Int(row.chapterNumber) == summary.number
                && row.startTime == summary.start
                && row.endTime == summary.end
                && row.title == summary.title
        }
        guard !unchanged else { return }

        for row in current { context.delete(row) }
        book.chapters = wanted.map { summary in
            let chapter = ChapterModel(
                title: summary.title,
                chapterNumber: Int16(clamping: summary.number),
                startTime: summary.start,
                endTime: summary.end
            )
            context.insert(chapter)
            return chapter
        }
        // The timeline the player reads lives in the manifest, so it has to follow.
        WatchLibraryDisk.writeManifest(bookID: book.id, chapters: wanted)
    }

    private func upsertBookmarks(_ incoming: [BookmarkSummary], on book: AudiobookModel, context: ModelContext) {
        var byID: [UUID: BookmarkModel] = [:]
        for bookmark in book.bookmarks { byID[bookmark.id] = bookmark }
        for summary in incoming {
            if let existing = byID[summary.id] {
                existing.timestamp = summary.timestamp
                existing.title = summary.title
                existing.dateCreated = summary.dateCreated
                continue
            }
            let bookmark = BookmarkModel(
                id: summary.id,
                title: summary.title,
                timestamp: summary.timestamp,
                dateCreated: summary.dateCreated
            )
            context.insert(bookmark)
            book.bookmarks.append(bookmark)
        }
    }

    /// The three books the "In progress" list shows, in the order the phone chose.
    func orderedBooks(from books: [AudiobookModel]) -> [AudiobookModel] {
        guard !bookOrder.isEmpty else { return books }
        let rank = Dictionary(bookOrder.enumerated().map { ($0.element, $0.offset) }) { first, _ in first }
        return books.sorted { (rank[$0.id] ?? .max, $0.title ?? "") < (rank[$1.id] ?? .max, $1.title ?? "") }
    }
}
