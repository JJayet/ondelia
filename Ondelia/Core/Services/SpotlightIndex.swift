import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Publishes the library to Spotlight, so a book can be found and opened from search.
///
/// Items carry the audiobook's UUID as their identifier; `IsoraApp` turns a tapped
/// result back into a `Isora://player` open.
enum SpotlightIndex {
    static let domain = "io.jayet.Isora.library"

    /// What an item shows; a book is reindexed only when this changes.
    nonisolated struct Entry: Hashable, Sendable {
        let title: String
        let author: String
    }

    /// Runs one update at a time, so an older run can never re-add a book a newer one removed.
    nonisolated private static let updater = Updater()

    /// Brings the index in line with the library. Runs after every library fetch, so only what
    /// changed since the last run is sent.
    nonisolated static func reindex(_ books: [(id: UUID, title: String, author: String)]) {
        let entries = Dictionary(
            books.map { ($0.id.uuidString, Entry(title: $0.title, author: $0.author)) },
            uniquingKeysWith: { first, _ in first }
        )
        Task(priority: .utility) { await updater.submit(entries) }
    }

    /// The ids to (re)index and the ids to drop to go from `old` to `new`.
    nonisolated static func diff(
        from old: [String: Entry],
        to new: [String: Entry]
    ) -> (changed: [String], removed: [String]) {
        let changed = new.filter { old[$0.key] != $0.value }.map(\.key)
        let removed = old.keys.filter { new[$0] == nil }
        return (changed.sorted(), removed.sorted())
    }

    private actor Updater {
        /// What the index holds, as far as this launch knows; nil until the first run.
        private var indexed: [String: Entry]?
        private var pending: [String: Entry]?
        private var running = false

        /// Runs submitted while one is in flight collapse into the latest.
        func submit(_ entries: [String: Entry]) async {
            pending = entries
            guard !running else { return }
            running = true
            while let next = pending {
                pending = nil
                await apply(next)
            }
            running = false
        }

        /// CoreSpotlight's types are not Sendable, so the items are built here from plain values.
        private func apply(_ entries: [String: Entry]) async {
            let index = CSSearchableIndex.default()
            do {
                // What an earlier launch indexed is unknown: its first run starts clean.
                if indexed == nil {
                    try await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain])
                }
                let (changed, removed) = SpotlightIndex.diff(from: indexed ?? [:], to: entries)
                if !removed.isEmpty {
                    try await index.deleteSearchableItems(withIdentifiers: removed)
                }
                let items = changed.compactMap { id in entries[id].map { item(id: id, $0) } }
                if !items.isEmpty {
                    try await index.indexSearchableItems(items)
                }
                indexed = entries
            } catch {
                // Unknown again: the next run starts clean.
                indexed = nil
                Log.library.error("❌ SpotlightIndex: \(error)")
            }
        }

        private func item(id: String, _ entry: Entry) -> CSSearchableItem {
            let attributes = CSSearchableItemAttributeSet(contentType: .audio)
            attributes.title = entry.title
            attributes.contentDescription = entry.author
            return CSSearchableItem(
                uniqueIdentifier: id,
                domainIdentifier: SpotlightIndex.domain,
                attributeSet: attributes
            )
        }
    }
}
