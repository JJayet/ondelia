import Foundation
import SwiftData

/// The AudiobookShelf sign-in the phone handed over, and what the watch does with it: stream a
/// linked book, and make a book of a server audiobook the listener starts here.
///
/// The token sits in this device's keychain; the server and the server library are not secrets.
@MainActor
@Observable
final class WatchServerAccount {
    static let shared = WatchServerAccount()

    private enum Keys {
        static let server = "audiobookshelf.server"
        static let library = "audiobookshelf.library"
        /// Not the phone's key: that item can reach this keychain through iCloud Keychain, and
        /// clearing it here would sign every device out.
        static let token = "watch.audiobookshelf.token"
    }

    private(set) var server: URL?
    private(set) var token: String?
    /// The server library the phone has selected, the only one the watch browses.
    private(set) var library: String?
    /// Items being made into books, so a second tap does not make a twin.
    private var joining: Set<String> = []

    var isSignedIn: Bool { server != nil && token != nil }
    var canBrowse: Bool { isSignedIn && library != nil }

    private init() {
        server = UserDefaults.standard.url(forKey: Keys.server)
        library = UserDefaults.standard.string(forKey: Keys.library)
        token = Keychain.get(Keys.token)
    }

    /// What the phone sent; nil signs the watch out.
    func apply(_ account: ServerAccount?) {
        Keychain.set(account?.token, for: Keys.token)
        UserDefaults.standard.set(account?.server, forKey: Keys.server)
        UserDefaults.standard.set(account?.library, forKey: Keys.library)
        server = account?.server
        token = account?.token
        library = account?.library
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
        isSignedIn && itemID(for: book) != nil
    }

    /// The book's timeline on the server, nil when it cannot be streamed right now.
    func streamTracks(for book: AudiobookModel) async -> [AudiobookTrack]? {
        guard let server, let token, let item = itemID(for: book) else { return nil }
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
        guard let server, let token else { throw AudiobookShelfAPI.Failure.http(401) }
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
        WatchLibraryStore.save()
        PhoneSyncService.shared.bookOrder.insert(book.id, at: 0)
        PhoneSyncService.shared.send(SyncEvent.joined(bookID: book.id, itemID: item.id))
        return book
    }
}
