import Foundation

// MARK: - What the Library, Search and Collections show
extension AudiobookShelfCatalog {
    /// The series by name, for listing them among the Collections. Empty while not shown;
    /// hidden ones left out.
    var seriesByName: [AudiobookShelfAPI.Series] {
        guard isActive else { return [] }
        return series.filter { !isHidden($0) }
    }

    /// The server collections by name, the same way.
    var collectionsByName: [AudiobookShelfAPI.Series] {
        guard isActive else { return [] }
        return collections.filter { !isHidden($0) }
    }

    func isHidden(_ group: AudiobookShelfAPI.Series) -> Bool {
        AudiobookShelfHidden.shared.isHidden(group.hiddenKind, group.id, on: serverID(forGroup: group.id))
    }

    /// Server audiobooks that have not joined the Library, given its books by server item, in
    /// the order `sort` asks for. Hidden ones left out.
    func unjoined(linked: [String: AudiobookModel], sortedFor sort: LibraryView.SortOption = .title) -> [AudiobookShelfAPI.Item] {
        guard isActive else { return [] }
        let hidden = AudiobookShelfHidden.shared
        return sorted.items(for: sort).filter {
            linked[$0.id] == nil && !hidden.isHidden($0, on: serverID(forItem: $0.id))
        }
    }

    /// The Library books to show. Streamed ones are left out while their server is not shown
    /// or does not answer, and when the listener hid them: only books with audio on this device,
    /// or with missing audio, are always there. Left out, never deleted.
    func visible(_ books: [AudiobookModel], linked: [String: AudiobookModel]) -> [AudiobookModel] {
        let manager = AudiobookManager.shared
        let hidden = AudiobookShelfHidden.shared
        let servers = service.itemServers
        let playable = Set(shownAccounts.filter { statuses[$0.id] != .unreachable }.map(\.id))
        var leftOut: Set<UUID> = []
        for (item, book) in linked where !manager.hasFile(book) {
            let server = servers[item] ?? service.primary?.id
            guard let server, playable.contains(server),
                  !hidden.isHidden(item: item, authors: book.author, on: server)
            else {
                leftOut.insert(book.id)
                continue
            }
        }
        return leftOut.isEmpty ? books : books.filter { !leftOut.contains($0.id) }
    }
}
