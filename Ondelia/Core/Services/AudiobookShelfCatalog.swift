import CryptoKit
import Foundation
import Observation

/// The selected server library's books, held in memory so the Library can show the ones it does
/// not hold yet beside its own (ADR 0002). Nothing here is stored: a server audiobook gets a
/// Library entry only when it joins, through `AudiobookShelfService.libraryBook(for:)`.
@MainActor
@Observable
final class AudiobookShelfCatalog {
    static let shared = AudiobookShelfCatalog()

    /// The listener's "Show server audiobooks in Library" switch. Synced by `SettingsSync`.
    static let enabledKey = "audiobookshelf.showInLibrary"

    enum Status: Equatable {
        case idle, loading, ready, unreachable
    }

    /// The server library's books, title order. `sorted` holds the other orders.
    var items: [AudiobookShelfAPI.Item] { sorted.byTitle }
    /// Each order the Library can ask for, sorted once per fetch off the main thread: sorting a
    /// few thousand titles with `localizedStandardCompare` on every redraw is what made a big
    /// server library feel slow.
    private(set) var sorted = Sorted()
    private(set) var status: Status = .idle
    /// The server library's series, each with its books in series order.
    private(set) var series: [AudiobookShelfAPI.Series] = [] {
        didSet { collectionSeries = Dictionary(series.map { (Self.collectionID(forSeries: $0.id), $0) }) { first, _ in first } }
    }
    private var collectionSeries: [UUID: AudiobookShelfAPI.Series] = [:]
    /// The server library `items` came from.
    private(set) var library: String?
    /// When `items` was fetched from the server, possibly by an earlier launch.
    private var fetchedAt: Date?
    private var loadedSnapshot = false
    private var fetching: Task<Void, Never>?

    /// How long a fetch stays good. Older, the next appearance refetches in the background
    /// while the stored copy stays on screen; pull to refresh always refetches.
    static let maxAge: TimeInterval = 15 * 60

    /// The series each server series Collection stands for, by the Collection's id.
    var seriesByCollection: [UUID: AudiobookShelfAPI.Series] {
        isActive ? collectionSeries : [:]
    }

    /// The id of the Collection that stands for a server series: derived from the series, so
    /// every device gives it the same id and the series needs no column of its own (a column
    /// would mean a new schema version). Two devices can still each make a record with that
    /// id before iCloud brings them the other's; `mergeDuplicateSeriesCollections` folds them.
    nonisolated static func collectionID(forSeries id: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("audiobookshelf-series:\(id)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 layout, name-based
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private let service = AudiobookShelfService.shared

    /// Read from defaults each time: views hold the same key in `@AppStorage`, which is what
    /// redraws them when it flips.
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Whether server audiobooks are shown: switched on, signed in, and the server answered.
    /// A fetch still running counts, so the Library does not flicker on every launch.
    var isActive: Bool { isEnabled && service.isSignedIn && status != .unreachable }

    /// The server was asked and did not answer, while the listener expects its audiobooks.
    var isUnreachable: Bool { isEnabled && service.isSignedIn && status == .unreachable }

    /// Brings the catalogue up to date, or forgets it when the switch is off or signed out.
    ///
    /// The last fetch is kept on disk, so a launch shows the server's audiobooks at once; the
    /// server is asked again only when that copy is older than `maxAge`, the server library
    /// changed, or `force` (pull to refresh). The fetch runs while the stored copy stays shown.
    func refresh(force: Bool = false) async {
        guard isEnabled, let server = service.server, service.token != nil else {
            forget()
            return
        }
        if !loadedSnapshot {
            loadedSnapshot = true
            await loadSnapshot(server: server)
        }
        let fresh = fetchedAt.map { Date().timeIntervalSince($0) < Self.maxAge } ?? false
        let sameLibrary = library != nil && library == service.selectedLibrary
        guard force || !fresh || !sameLibrary || status == .unreachable else { return }
        // One fetch at a time: a second caller waits for the one already running.
        if let fetching { return await fetching.value }
        let task = Task { await fetch() }
        fetching = task
        await task.value
        fetching = nil
    }

    private func fetch() async {
        guard let server = service.server, let token = service.token else { return }
        if items.isEmpty { status = .loading }
        do {
            let library = try await selectedLibrary(server: server, token: token)
            async let fetched = AudiobookShelfAPI.allItems(server: server, token: token, library: library)
            async let fetchedSeries = AudiobookShelfAPI.allSeries(server: server, token: token, library: library)
            let snapshot = Snapshot(
                server: server.absoluteString, library: library, fetchedAt: Date(),
                items: try await fetched, series: try await fetchedSeries
            )
            await apply(snapshot)
            let url = Self.snapshotURL
            Task.detached(priority: .utility) {
                try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            }
        } catch is CancellationError {
            if status == .loading { status = .idle }
        } catch {
            // The stored copy stays in memory for when the server answers again, but while it
            // does not, its audiobooks are not shown: they could not play.
            Log.library.error("AudiobookShelf: catalogue unavailable: \(error.localizedDescription)")
            status = .unreachable
        }
    }

    /// Takes a fetched or stored catalogue in, sorting it off the main thread first.
    private func apply(_ snapshot: Snapshot) async {
        let items = snapshot.items
        sorted = await Task.detached(priority: .userInitiated) { Sorted(items) }.value
        series = snapshot.series
        library = snapshot.library
        fetchedAt = snapshot.fetchedAt
        status = .ready
        AudiobookManager.shared.reconcileServerSeriesCollections()
    }

    private func loadSnapshot(server: URL) async {
        let url = Self.snapshotURL
        let stored = await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        }.value
        guard let stored, stored.server == server.absoluteString else { return }
        await apply(stored)
    }

    /// Drops the catalogue, in memory and on disk: the switch went off, or the account went.
    func forget() {
        fetching?.cancel()
        fetching = nil
        sorted = Sorted()
        series = []
        library = nil
        fetchedAt = nil
        status = .idle
        loadedSnapshot = false
        try? FileManager.default.removeItem(at: Self.snapshotURL)
    }

    /// Caches, not Application Support: the server has it all, so the system may purge it.
    nonisolated static var snapshotURL: URL {
        URL.cachesDirectory.appending(path: "AudiobookShelfCatalog.json")
    }

    /// What is stored between launches.
    private struct Snapshot: Codable {
        let server: String
        let library: String
        let fetchedAt: Date
        let items: [AudiobookShelfAPI.Item]
        let series: [AudiobookShelfAPI.Series]
    }

    /// The server's books in each order the Library sorts by.
    struct Sorted: Sendable {
        var byTitle: [AudiobookShelfAPI.Item] = []
        var byAuthor: [AudiobookShelfAPI.Item] = []
        var byDateAdded: [AudiobookShelfAPI.Item] = []

        init() {}

        nonisolated init(_ items: [AudiobookShelfAPI.Item]) {
            func titleOrder(_ lhs: AudiobookShelfAPI.Item, _ rhs: AudiobookShelfAPI.Item) -> Bool {
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            byTitle = items.sorted(by: titleOrder)
            byAuthor = byTitle.sorted { lhs, rhs in
                let names = (lhs.author ?? "").localizedStandardCompare(rhs.author ?? "")
                return names == .orderedSame ? titleOrder(lhs, rhs) : names == .orderedAscending
            }
            byDateAdded = byTitle.sorted { lhs, rhs in
                lhs.dateAdded == rhs.dateAdded ? titleOrder(lhs, rhs) : lhs.dateAdded > rhs.dateAdded
            }
        }

        /// The order `LibraryEntry.merged` expects for `sort`.
        func items(for sort: LibraryView.SortOption) -> [AudiobookShelfAPI.Item] {
            switch sort {
            case .author: byAuthor
            case .dateAdded: byDateAdded
            case .title, .lastPlayed, .progress: byTitle
            }
        }
    }

    /// The saved server library, or the first one, which then becomes the saved one.
    private func selectedLibrary(server: URL, token: String) async throws -> String {
        let libraries = try await AudiobookShelfAPI.libraries(server: server, token: token)
        if let saved = service.selectedLibrary, libraries.contains(where: { $0.id == saved }) { return saved }
        guard let first = libraries.first?.id else { throw AudiobookShelfAPI.Failure.unexpectedResponse }
        service.selectedLibrary = first
        return first
    }

    /// Server audiobooks that have not joined the Library, given its books by server item, in
    /// the order `sort` asks for.
    func unjoined(linked: [String: AudiobookModel], sortedFor sort: LibraryView.SortOption = .title) -> [AudiobookShelfAPI.Item] {
        guard isActive else { return [] }
        return sorted.items(for: sort).filter { linked[$0.id] == nil }
    }

    /// The Library books to show. While the server is off, streamed ones are hidden: only books
    /// with audio on this device, or with missing audio, are left. Hidden, never deleted.
    func visible(_ books: [AudiobookModel], linked: [String: AudiobookModel]) -> [AudiobookModel] {
        guard !isActive else { return books }
        let streamed = Set(linked.values.map(\.id))
        let manager = AudiobookManager.shared
        return books.filter { !streamed.contains($0.id) || manager.hasFile($0) }
    }
}
