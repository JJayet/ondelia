import Foundation
import SwiftUI

/// Books stacked to be read next. When the playing book ends, `GlobalAudioManager` pops the
/// head of this queue and plays it.
///
/// Only the ids are kept, in `UserDefaults` — the books themselves already live in SwiftData,
/// so there is nothing here worth a schema of its own.
@MainActor
@Observable
final class PlayQueue {
    static let shared = PlayQueue()

    private static let defaultsKey = "playQueue.bookIDs"

    /// Ordered book ids, first = next to play.
    private(set) var bookIDs: [UUID]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookIDs = (defaults.stringArray(forKey: Self.defaultsKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    func contains(_ book: AudiobookModel) -> Bool { bookIDs.contains(book.id) }

    func append(_ book: AudiobookModel) {
        guard !contains(book) else { return }
        bookIDs.append(book.id)
        save()
    }

    func remove(_ book: AudiobookModel) {
        guard let index = bookIDs.firstIndex(of: book.id) else { return }
        bookIDs.remove(at: index)
        save()
    }

    func toggle(_ book: AudiobookModel) {
        contains(book) ? remove(book) : append(book)
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        bookIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    /// A Merge puts the merged audiobook where the first of its queued sources was.
    func replace(_ sourceIDs: Set<UUID>, with mergedID: UUID) {
        let replaced = bookIDs.replacingSources(sourceIDs, with: mergedID)
        guard replaced != bookIDs else { return }
        bookIDs = replaced
        save()
    }

    /// Books in queue order, resolved against a library. Ids with no book are skipped, not
    /// removed: this is read from view bodies, and writing state there is a SwiftUI violation.
    /// `popNext` prunes them.
    func books(in library: [AudiobookModel]) -> [AudiobookModel] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return bookIDs.compactMap { byID[$0] }
    }

    /// Removes and returns the first queued book found in `library`, nil if empty. Stale ids —
    /// a queued book deleted while the app was not running — are dropped on the way.
    func popNext(from library: [AudiobookModel]) -> AudiobookModel? {
        let resolved = books(in: library)
        guard let next = resolved.first else {
            if !bookIDs.isEmpty { bookIDs = []; save() }
            return nil
        }
        bookIDs = resolved.dropFirst().map(\.id)
        save()
        return next
    }

    private func save() {
        defaults.set(bookIDs.map(\.uuidString), forKey: Self.defaultsKey)
    }
}
