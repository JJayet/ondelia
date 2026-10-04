import Foundation
import SwiftData

/// The AudiobookShelf sign-ins the phone handed over, and what the watch does with them: stream
/// a linked book from its server, and make a book of a server audiobook the listener starts here.
///
/// Tokens sit in this device's keychain; servers and server libraries are not secrets.
@MainActor
@Observable
final class WatchServerAccount {
    static let shared = WatchServerAccount()

    private enum Keys {
        static let accounts = "audiobookshelf.watch.accounts"
        static let browsing = "audiobookshelf.watch.browsing"
        /// Before several servers.
        static let server = "audiobookshelf.server"
        static let library = "audiobookshelf.library"
        /// Not the phone's keys: those items can reach this keychain through iCloud Keychain, and
        /// clearing them here would sign every device out.
        static let token = "watch.audiobookshelf.token"
        static func token(_ key: String) -> String { "watch.audiobookshelf.token.\(key)" }
    }

    /// What is kept in defaults: everything but the token.
    private struct Stored: Codable {
        let id: String?
        let server: URL
        let library: String?
    }

    private(set) var accounts: [ServerAccount] = []
    /// The server the Server screen browses; nil: the first.
    var browsingKey: String? {
        didSet { UserDefaults.standard.set(browsingKey, forKey: Keys.browsing) }
    }
    /// Items being made into books, so a second tap does not make a twin.
    private var joining: Set<String> = []

    var browsing: ServerAccount? { accounts.first { Self.key($0) == browsingKey } ?? accounts.first }
    var server: URL? { browsing?.server }
    var token: String? { browsing?.token }
    /// The server library the phone has selected on the browsed server.
    var library: String? { browsing?.library }

    var isSignedIn: Bool { !accounts.isEmpty }
    var canBrowse: Bool { browsing?.library != nil }

    /// The phone's id, or the address for an account from a phone build before several servers.
    static func key(_ account: ServerAccount) -> String { account.id ?? account.server.absoluteString }

    private init() {
        browsingKey = UserDefaults.standard.string(forKey: Keys.browsing)
        if let data = UserDefaults.standard.data(forKey: Keys.accounts),
           let stored = try? JSONDecoder().decode([Stored].self, from: data) {
            accounts = stored.compactMap { entry in
                let key = entry.id ?? entry.server.absoluteString
                return Keychain.get(Keys.token(key)).map { ServerAccount(id: entry.id, server: entry.server, token: $0, library: entry.library) }
            }
        } else if let server = UserDefaults.standard.url(forKey: Keys.server), let token = Keychain.get(Keys.token) {
            accounts = [ServerAccount(server: server, token: token, library: UserDefaults.standard.string(forKey: Keys.library))]
        }
    }

    /// What the phone sent; empty signs the watch out.
    func apply(_ next: [ServerAccount]) {
        let kept = Set(next.map(Self.key))
        for account in accounts where !kept.contains(Self.key(account)) {
            Keychain.set(nil, for: Keys.token(Self.key(account)))
        }
        Keychain.set(nil, for: Keys.token)
        for account in next { Keychain.set(account.token, for: Keys.token(Self.key(account))) }
        let stored = next.map { Stored(id: $0.id, server: $0.server, library: $0.library) }
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: Keys.accounts)
        accounts = next
    }

    /// From a phone build before several servers: one account or none.
    func apply(_ account: ServerAccount?) {
        // A phone that sends the list sends this too, for older watches: the list wins.
        guard accounts.allSatisfy({ $0.id == nil }) else { return }
        apply(account.map { [$0] } ?? [])
    }

    /// The server an item lives on: the one the phone said, or the browsed one.
    func account(forItem itemID: String) -> ServerAccount? {
        var records = FetchDescriptor<AudiobookShelfItemServerModel>(predicate: #Predicate { $0.itemID == itemID })
        records.fetchLimit = 1
        let serverID = (try? context.fetch(records))?.first?.serverID
        return accounts.first { $0.id != nil && $0.id == serverID } ?? browsing
    }

    func recordServer(_ serverID: String?, of itemID: String) {
        guard let serverID else { return }
        var records = FetchDescriptor<AudiobookShelfItemServerModel>(predicate: #Predicate { $0.itemID == itemID })
        records.fetchLimit = 1
        if let existing = (try? context.fetch(records))?.first {
            existing.serverID = serverID
        } else {
            context.insert(AudiobookShelfItemServerModel(itemID: itemID, serverID: serverID))
        }
    }

    // MARK: - Links

    private var context: ModelContext { WatchLibraryStore.shared.context }

    func itemID(for book: AudiobookModel) -> String? {
        link(audiobookID: book.id)?.itemID
    }

    func book(forItem itemID: String) -> AudiobookModel? {
        var links = FetchDescriptor<AudiobookShelfLinkModel>(predicate: #Predicate { $0.itemID == itemID })
        links.fetchLimit = 1
        guard let bookID = (try? context.fetch(links))?.first?.audiobookID else { return nil }
        var books = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == bookID })
        books.fetchLimit = 1
        return (try? context.fetch(books))?.first
    }

    /// Mirrors the phone's link for a book it sent. Saved by the snapshot that calls it.
    func setLink(itemID: String?, for bookID: UUID) {
        let existing = link(audiobookID: bookID)
        guard existing?.itemID != itemID else { return }
        if let existing { context.delete(existing) }
        guard let itemID else { return }
        context.insert(AudiobookShelfLinkModel(audiobookID: bookID, itemID: itemID))
    }

    private func link(audiobookID: UUID) -> AudiobookShelfLinkModel? {
        var descriptor = FetchDescriptor<AudiobookShelfLinkModel>(predicate: #Predicate { $0.audiobookID == audiobookID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Streaming

    func canStream(_ book: AudiobookModel) -> Bool {
        guard let item = itemID(for: book) else { return false }
        return account(forItem: item) != nil
    }

    /// The book's timeline on the server, nil when it cannot be streamed right now.
    func streamTracks(for book: AudiobookModel) async -> [AudiobookTrack]? {
        guard let item = itemID(for: book), let account = account(forItem: item) else { return nil }
        let (server, token) = (account.server, account.token)
        do {
            let playback = try await AudiobookShelfAPI.playbackItem(server: server, token: token, item: item)
            let headers = ["Authorization": "Bearer \(token)"]
            return (playback.media.tracks ?? []).map { track in
                AudiobookTrack(
                    url: AudiobookShelfAPI.streamURL(server: server, contentPath: track.contentUrl),
                    start: track.startOffset,
                    duration: track.duration,
                    httpHeaders: headers
                )
            }
        } catch {
            Log.audio.error("❌ WatchServerAccount: stream unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    /// The book for a server audiobook: the one already here, or a new one the phone is told
    /// about, so it joins the Library under the same id.
    func join(_ item: AudiobookShelfAPI.Item) async throws -> AudiobookModel? {
        if let existing = book(forItem: item.id) { return existing }
        guard let account = browsing else { throw AudiobookShelfAPI.Failure.http(401) }
        let (server, token) = (account.server, account.token)
        guard !joining.contains(item.id) else { return nil }
        joining.insert(item.id)
        defer { joining.remove(item.id) }

        let playback = try await AudiobookShelfAPI.playbackItem(server: server, token: token, item: item.id)
        let cover = try? await URLSession.shared.data(
            for: AudiobookShelfAPI.coverRequest(server: server, token: token, item: item.id, width: 256)
        )
        let book = AudiobookModel(
            title: playback.media.metadata.title ?? item.title,
            author: playback.author ?? item.author,
            duration: playback.media.duration ?? item.media.duration ?? 0,
            coverImageData: (cover?.1 as? HTTPURLResponse)?.statusCode == 200 ? cover?.0 : nil,
            lastPlayed: Date()
        )
        context.insert(book)
        book.chapters = (playback.media.chapters ?? []).enumerated().map { index, chapter in
            let row = ChapterModel(
                title: chapter.title,
                chapterNumber: Int16(clamping: index + 1),
                startTime: chapter.start,
                endTime: chapter.end
            )
            context.insert(row)
            return row
        }
        context.insert(AudiobookShelfLinkModel(audiobookID: book.id, itemID: item.id))
        recordServer(account.id, of: item.id)
        WatchLibraryStore.save()
        PhoneSyncService.shared.bookOrder.insert(book.id, at: 0)
        PhoneSyncService.shared.send(SyncEvent.joined(bookID: book.id, itemID: item.id, serverID: account.id))
        return book
    }
}
