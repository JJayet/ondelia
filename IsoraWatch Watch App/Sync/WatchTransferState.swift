import Foundation

/// Where one chapter stands, as far as this watch can tell.
enum ChapterTransferState: Equatable {
    case ready(bytes: Int64)
    case receiving(fraction: Double)
    /// Asked for, nothing arriving yet — the phone may still be exporting it.
    case queued
    case missing

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Per-chapter transfer state, read by every view that shows a dot next to a chapter.
///
/// Only the *sender* sees `WCSessionFileTransfer.progress`, so the fraction is whatever the
/// phone last forwarded; the ground truth is the disk inventory, which always wins.
@MainActor
@Observable
final class WatchTransferState {
    static let shared = WatchTransferState()

    private struct Key: Hashable {
        let bookID: UUID
        let chapter: Int
    }

    private var readyBytes: [Key: Int64] = [:]
    private var fractions: [Key: Double] = [:]
    private var requested: Set<Key> = []

    private init() {
        refreshAll()
    }

    func state(bookID: UUID, chapter: Int) -> ChapterTransferState {
        let key = Key(bookID: bookID, chapter: chapter)
        if let bytes = readyBytes[key] { return .ready(bytes: bytes) }
        if let fraction = fractions[key] { return .receiving(fraction: fraction) }
        if requested.contains(key) { return .queued }
        return .missing
    }

    /// Chapters of this book that are on disk, cheapest source for a status line.
    func readyChapters(bookID: UUID) -> [Int] {
        readyBytes.keys.filter { $0.bookID == bookID }.map(\.chapter).sorted()
    }

    /// The best fraction to show for a book that is receiving something, nil when nothing is.
    func incomingFraction(bookID: UUID) -> Double? {
        fractions.filter { $0.key.bookID == bookID }.values.max()
    }

    func hasRequest(bookID: UUID, chapter: Int) -> Bool {
        let key = Key(bookID: bookID, chapter: chapter)
        return requested.contains(key) || fractions[key] != nil
    }

    // MARK: - Mutations

    func markRequested(bookID: UUID, chapter: Int) {
        requested.insert(Key(bookID: bookID, chapter: chapter))
    }

    func markProgress(bookID: UUID, chapter: Int, fraction: Double) {
        let key = Key(bookID: bookID, chapter: chapter)
        requested.remove(key)
        fractions[key] = min(max(fraction, 0), 1)
    }

    /// Rescans one book's folder. Called whenever a file lands or is deleted — the in-flight
    /// bookkeeping is a hint, this is the fact.
    func refresh(bookID: UUID) {
        for key in readyBytes.keys where key.bookID == bookID { readyBytes[key] = nil }
        for number in WatchLibraryDisk.chaptersOnDisk(bookID: bookID) {
            let key = Key(bookID: bookID, chapter: number)
            readyBytes[key] = WatchLibraryDisk.byteCount(bookID: bookID, number: number)
            fractions[key] = nil
            requested.remove(key)
        }
    }

    func refreshAll() {
        readyBytes.removeAll()
        for bookID in WatchLibraryDisk.bookIDsWithContent() { refresh(bookID: bookID) }
    }

    func forget(bookID: UUID) {
        readyBytes = readyBytes.filter { $0.key.bookID != bookID }
        fractions = fractions.filter { $0.key.bookID != bookID }
        requested = requested.filter { $0.bookID != bookID }
    }

    func forgetEverything() {
        readyBytes.removeAll()
        fractions.removeAll()
        requested.removeAll()
    }
}
