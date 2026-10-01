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

    private(set) var items: [AudiobookShelfAPI.Item] = []
    private(set) var status: Status = .idle
    /// The server library `items` came from.
    private(set) var library: String?

    private let service = AudiobookShelfService.shared

    /// Read from defaults each time: views hold the same key in `@AppStorage`, which is what
    /// redraws them when it flips.
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Whether server audiobooks are shown: switched on, signed in, and the server answered.
    /// A fetch still running counts, so the Library does not flicker on every launch.
    var isActive: Bool { isEnabled && service.isSignedIn && status != .unreachable }

    /// The server was asked and did not answer, while the listener expects its audiobooks.
    var isUnreachable: Bool { isEnabled && service.isSignedIn && status == .unreachable }

    /// Fetches the whole selected server library, or forgets it when the switch is off.
    ///
    /// ponytail: the whole library in memory, refetched on appear and on pull to refresh. Fine
    /// for a few thousand minified items; add a disk cache if a big library feels slow.
    func refresh() async {
        guard isEnabled, let server = service.server, let token = service.token else {
            items = []
            library = nil
            status = .idle
            return
        }
        status = .loading
        do {
            let library = try await selectedLibrary(server: server, token: token)
            let fetched = try await AudiobookShelfAPI.allItems(server: server, token: token, library: library)
            items = fetched
            self.library = library
            status = .ready
        } catch is CancellationError {
            status = items.isEmpty ? .idle : .ready
        } catch {
            Log.library.error("AudiobookShelf: catalogue unavailable: \(error.localizedDescription)")
            items = []
            status = .unreachable
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

    /// Server audiobooks that have not joined the Library, given its books by server item.
    func unjoined(linked: [String: AudiobookModel]) -> [AudiobookShelfAPI.Item] {
        guard isActive else { return [] }
        return items.filter { linked[$0.id] == nil }
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
