import CryptoKit
import Foundation
import Observation

/// Each shown server's selected server library, held in memory so the Library can show the
/// books it does not hold yet beside its own (ADR 0002, ADR 0004). Nothing here is stored: a
/// server audiobook gets a Library entry only when it joins, through
/// `AudiobookShelfService.libraryBook(for:)`.
///
/// One `Part` per server, fetched on its own; the Library reads them merged. A server that does
/// not answer drops out of the merge on its own, and only its audiobooks vanish.
@MainActor
@Observable
final class AudiobookShelfCatalog {
    static let shared = AudiobookShelfCatalog()

    /// The listener's "Show server audiobooks in Library" switch. Synced by `SettingsSync`.
    static let enabledKey = "audiobookshelf.showInLibrary"

    enum Status: Equatable {
        case idle, loading, ready, unreachable
    }

    /// One server's catalogue: what is stored between launches, plus how its last fetch went.
    struct Part: Codable {
        let library: String
        let fetchedAt: Date
        let items: [AudiobookShelfAPI.Item]
        let series: [AudiobookShelfAPI.Series]
        var collections: [AudiobookShelfAPI.Series]?
    }

    /// By account id.
    private(set) var parts: [String: Part] = [:]
    private(set) var statuses: [String: Status] = [:]
    private var fetching: [String: Task<Void, Never>] = [:]
    private var loadedSnapshots: Set<String> = []

    /// Every merged book, title order. `sorted` holds the other orders.
    var items: [AudiobookShelfAPI.Item] { sorted.byTitle }
    /// Each order the Library can ask for, sorted once per change off the main thread: sorting a
    /// few thousand titles with `localizedStandardCompare` on every redraw is what made a big
    /// server library feel slow.
    private(set) var sorted = Sorted()
    /// The merged series and collections (`isServerCollection`), each in the server's order.
    private(set) var series: [AudiobookShelfAPI.Series] = []
    private(set) var collections: [AudiobookShelfAPI.Series] = []
    /// Which server each item, series and collection comes from: ids are UUIDs, unique across
    /// servers.
    private(set) var itemServers: [String: String] = [:]
    private(set) var groupServers: [String: String] = [:]
    private var collectionSeries: [UUID: AudiobookShelfAPI.Series] = [:]

    /// How long a fetch stays good. Older, the next appearance refetches in the background
    /// while the stored copy stays on screen; pull to refresh always refetches.
    static let maxAge: TimeInterval = 15 * 60

    let service = AudiobookShelfService.shared

    /// Read from defaults each time: views hold the same key in `@AppStorage`, which is what
    /// redraws them when it flips.
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// The servers whose audiobooks are shown: switched on, each one signed in and shown.
    var shownAccounts: [AudiobookShelfAccount] {
        guard isEnabled else { return [] }
        return service.accounts.filter { $0.showsInLibrary && service.token(for: $0) != nil }
    }

    /// Whether server audiobooks are shown: some server is, and not every one failed to answer.
    /// A fetch still running counts, so the Library does not flicker on every launch.
    var isActive: Bool { shownAccounts.contains { statuses[$0.id] != .unreachable } }

    /// Some shown server was asked and did not answer.
    var isUnreachable: Bool { !unreachableAccounts.isEmpty }
    var unreachableAccounts: [AudiobookShelfAccount] { shownAccounts.filter { statuses[$0.id] == .unreachable } }

    /// Some server's catalogue is in, so Collections can be reconciled against it.
    var isReady: Bool { statuses.values.contains(.ready) }

    /// Series and collections, each one a Collection once the Library holds one of its books.
    var groups: [AudiobookShelfAPI.Series] { series + collections }

    /// The series each server series or server collection Collection stands for, by its id.
    var seriesByCollection: [UUID: AudiobookShelfAPI.Series] {
        isActive ? collectionSeries : [:]
    }

    func serverID(forItem id: String) -> String? { itemServers[id] }
    func serverID(forGroup id: String) -> String? { groupServers[id] }
    func library(of serverID: String) -> String? { parts[serverID]?.library }

    /// Brings every shown server's catalogue up to date, and forgets the others.
    ///
    /// The last fetch is kept on disk, so a launch shows the servers' audiobooks at once; a
    /// server is asked again only when its copy is older than `maxAge`, its server library
    /// changed, or `force` (pull to refresh). The fetches run side by side, the stored copies
    /// staying shown meanwhile.
    func refresh(force: Bool = false) async {
        let shown = shownAccounts
        for id in Set(parts.keys).union(statuses.keys) where !shown.contains(where: { $0.id == id }) {
            forget(id)
        }
        await withTaskGroup(of: Void.self) { group in
            for account in shown {
                group.addTask { await self.refresh(account, force: force) }
            }
        }
    }

    private func refresh(_ account: AudiobookShelfAccount, force: Bool) async {
        if !loadedSnapshots.contains(account.id) {
            loadedSnapshots.insert(account.id)
            await loadSnapshot(account)
        }
        let part = parts[account.id]
        let fresh = part.map { Date().timeIntervalSince($0.fetchedAt) < Self.maxAge } ?? false
        let sameLibrary = part != nil && part?.library == account.library
        guard force || !fresh || !sameLibrary || statuses[account.id] == .unreachable else { return }
        // One fetch per server at a time: a second caller waits for the one already running.
        if let running = fetching[account.id] { return await running.value }
        let task = Task { await fetch(account) }
        fetching[account.id] = task
        await task.value
        fetching[account.id] = nil
    }

    private func fetch(_ account: AudiobookShelfAccount) async {
        guard let token = service.token(for: account) else { return }
        let server = account.server
        if parts[account.id] == nil { statuses[account.id] = .loading }
        do {
            let library = try await selectedLibrary(of: account, token: token)
            async let fetched = AudiobookShelfAPI.allItems(server: server, token: token, library: library)
            async let fetchedSeries = AudiobookShelfAPI.allSeries(server: server, token: token, library: library)
            // Optional: a server without collections, or one refusing them, still shows its books.
            async let fetchedCollections = try? AudiobookShelfAPI.collections(server: server, token: token, library: library)
            let part = Part(
                library: library, fetchedAt: Date(),
                items: try await fetched, series: try await fetchedSeries, collections: await fetchedCollections
            )
            await apply(part, for: account.id)
            let url = Self.snapshotURL(for: account.id)
            Task.detached(priority: .utility) {
                try? JSONEncoder().encode(part).write(to: url, options: .atomic)
            }
        } catch is CancellationError {
            if statuses[account.id] == .loading { statuses[account.id] = .idle }
        } catch {
            // The stored copy stays in memory for when the server answers again, but while it
            // does not, its audiobooks are not shown: they could not play.
            Log.library.error("AudiobookShelf: catalogue unavailable: \(error.localizedDescription)")
            statuses[account.id] = .unreachable
            await merge()
        }
    }

    private func apply(_ part: Part, for serverID: String) async {
        parts[serverID] = part
        statuses[serverID] = .ready
        await merge()
        AudiobookManager.shared.reconcileServerSeriesCollections()
        // It waits on the catalogue for books from a server: see `serverSeriesShowAll`.
        AudiobookManager.shared.reconcileSeriesCollections()
    }

    /// Rebuilds the merged lists from the servers that answer, sorting off the main thread.
    private func merge() async {
        let reachable = parts.filter { statuses[$0.key] != .unreachable }
        let all = reachable.values.flatMap(\.items)
        sorted = await Task.detached(priority: .userInitiated) { Sorted(all) }.value
        let byName = { (lhs: AudiobookShelfAPI.Series, rhs: AudiobookShelfAPI.Series) in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        // One server keeps the server's own order, as before several servers.
        series = reachable.count == 1 ? reachable.values.flatMap(\.series) : reachable.values.flatMap(\.series).sorted(by: byName)
        collections = reachable.values.flatMap { $0.collections ?? [] }.sorted(by: byName)
        var items: [String: String] = [:]
        var groups: [String: String] = [:]
        for (serverID, part) in parts {
            for item in part.items { items[item.id] = serverID }
            for group in part.series + (part.collections ?? []) { groups[group.id] = serverID }
        }
        itemServers = items
        groupServers = groups
        collectionSeries = Dictionary((series + collections).map { (Self.collectionID(for: $0), $0) }) { first, _ in first }
    }

    private func loadSnapshot(_ account: AudiobookShelfAccount) async {
        let url = Self.snapshotURL(for: account.id)
        let stored = await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Part.self, from: $0) }
        }.value
        guard let stored else { return }
        await apply(stored, for: account.id)
    }

    /// Drops one server's catalogue, in memory and on disk: it is no longer shown or signed in.
    func forget(_ serverID: String) {
        fetching.removeValue(forKey: serverID)?.cancel()
        parts[serverID] = nil
        statuses[serverID] = nil
        loadedSnapshots.remove(serverID)
        try? FileManager.default.removeItem(at: Self.snapshotURL(for: serverID))
        Task { await merge() }
    }

    /// Drops every server's catalogue: the switch went off.
    func forget() {
        for id in Set(parts.keys).union(statuses.keys) { forget(id) }
        // Left by versions before several servers.
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "AudiobookShelfCatalog.json"))
    }

    /// Caches, not Application Support: the server has it all, so the system may purge it.
    nonisolated static func snapshotURL(for serverID: String) -> URL {
        URL.cachesDirectory.appending(path: "AudiobookShelfCatalog-\(serverID).json")
    }

    /// The account's saved server library, or its first one, which then becomes the saved one.
    private func selectedLibrary(of account: AudiobookShelfAccount, token: String) async throws -> String {
        let libraries = try await AudiobookShelfAPI.libraries(server: account.server, token: token)
        if let saved = account.library, libraries.contains(where: { $0.id == saved }) { return saved }
        guard let first = libraries.first?.id else { throw AudiobookShelfAPI.Failure.unexpectedResponse }
        service.setLibrary(first, for: account.id)
        return first
    }

    /// The id of the Collection that stands for a server series: derived from the series, so
    /// every device gives it the same id and the series needs no column of its own (a column
    /// would mean a new schema version). Two devices can still each make a record with that
    /// id before iCloud brings them the other's; `mergeDuplicateSeriesCollections` folds them.
    nonisolated static func collectionID(forSeries id: String) -> UUID {
        derivedID("audiobookshelf-series:\(id)")
    }

    /// The id of the Collection that stands for a server series or server collection.
    nonisolated static func collectionID(for group: AudiobookShelfAPI.Series) -> UUID {
        group.isServerCollection ? derivedID("audiobookshelf-collection:\(group.id)") : collectionID(forSeries: group.id)
    }

    private nonisolated static func derivedID(_ name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 layout, name-based
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
