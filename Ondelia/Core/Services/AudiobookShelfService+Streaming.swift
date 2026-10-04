import Foundation
import SwiftData

/// Playing a server book without downloading it.
///
/// A streamed book is an ordinary library entry with no file, linked to its server item, so
/// progress, bookmarks, statistics, Continue Reading, Now Playing, CarPlay and iCloud sync all
/// treat it like any other book. The player asks here for its tracks when it has no file.
extension AudiobookShelfService {
    /// The server item a library book came from, if any.
    func itemID(for book: AudiobookModel) -> String? {
        guard SwiftDataController.shared.isLoaded else { return nil }
        let id = book.id
        var descriptor = FetchDescriptor<AudiobookShelfLinkModel>(predicate: #Predicate { $0.audiobookID == id })
        descriptor.fetchLimit = 1
        return (try? SwiftDataController.shared.context.fetch(descriptor))?.first?.itemID
    }

    /// Whether the book can play from the server: signed in, linked, and not on this device.
    func canStream(_ book: AudiobookModel) -> Bool {
        isSignedIn && !AudiobookManager.shared.hasFile(book) && itemID(for: book) != nil
    }

    /// Downloads a streamed book, sized from the catalogue when it lists the item.
    func download(_ book: AudiobookModel) {
        guard let item = itemID(for: book) else { return }
        let size = AudiobookShelfCatalog.shared.items.first { $0.id == item }?.size
        download(id: item, title: book.title ?? "", author: book.author, size: size)
    }

    /// The book's timeline on the server, or nil when it is not a book to stream. A failed
    /// request is reported through `problem` and also returns nil; the load then fails.
    func streamTracks(for book: AudiobookModel) async -> [AudiobookTrack]? {
        guard canStream(book), let item = itemID(for: book), let server, let token else { return nil }
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
            Log.audio.error("AudiobookShelf: stream unavailable: \(error.localizedDescription)")
            problem = Problem(
                title: NSLocalizedString("Couldn't Play", comment: "AudiobookShelf: streaming failed title"),
                message: error.localizedDescription
            )
            return nil
        }
    }

    /// The library entry to stream `item` under, or nil after reporting why there is none.
    /// A second tap while the first is still fetching is ignored rather than making a twin.
    func streamingBook(for item: AudiobookShelfAPI.Item) async -> AudiobookModel? {
        guard !preparingStreams.contains(item.id) else { return nil }
        preparingStreams.insert(item.id)
        defer { preparingStreams.remove(item.id) }
        do {
            return try await libraryBook(for: item)
        } catch {
            problem = Problem(
                title: NSLocalizedString("Couldn't Play", comment: "AudiobookShelf: streaming failed title"),
                message: error.localizedDescription
            )
            return nil
        }
    }

    /// The library entry for `item`: the existing one, or a new one made from the server's
    /// metadata, chapters and cover.
    func libraryBook(for item: AudiobookShelfAPI.Item) async throws -> AudiobookModel {
        try await libraryBook(itemID: item.id, title: item.title, author: item.author, duration: item.media.duration)
    }

    /// `id` is the watch's, when the watch streamed the book first and already uses that id.
    func libraryBook(
        itemID: String,
        id: UUID = UUID(),
        title: String = "",
        author: String? = nil,
        duration: Double? = nil
    ) async throws -> AudiobookModel {
        if let existing = libraryBooks[itemID] { return existing }
        guard let server, let token else { throw AudiobookShelfAPI.Failure.http(401) }

        let playback = try await AudiobookShelfAPI.playbackItem(server: server, token: token, item: itemID)
        let cover = try? await URLSession.shared.data(
            for: AudiobookShelfAPI.coverRequest(server: server, token: token, item: itemID, width: 800)
        )
        // The requests took a while; a tap on the same book in the meantime may have made it.
        if let existing = libraryBooks[itemID] { return existing }

        let book = AudiobookModel(
            id: id,
            title: playback.media.metadata.title ?? title,
            author: playback.author ?? author,
            narrator: playback.narrator,
            fileURL: nil,
            duration: playback.media.duration ?? duration ?? 0,
            coverImageData: (cover?.1 as? HTTPURLResponse)?.statusCode == 200 ? cover?.0 : nil
        )
        let context = SwiftDataController.shared.context
        context.insert(book)
        for (index, chapter) in (playback.media.chapters ?? []).enumerated() {
            let row = ChapterModel(
                title: chapter.title,
                chapterNumber: Int16(clamping: index + 1),
                startTime: chapter.start,
                endTime: chapter.end
            )
            context.insert(row)
            row.audiobook = book
        }
        Self.insertLink(audiobookID: book.id, itemID: itemID, serverID: primary?.id, context: context)
        SwiftDataController.shared.save()
        linksDidChange()
        AudiobookManager.shared.fetchAudiobooks()
        return book
    }

    /// A download of a book the user was streaming: the downloaded file moves onto the entry
    /// that holds their position, bookmarks and statistics, and the entry the import just made
    /// goes. Otherwise the library would hold the book twice.
    static func adopt(_ imported: AudiobookModel, into streamed: AudiobookModel, context: ModelContext) {
        streamed.fileURL = imported.fileURL
        if imported.duration > 0 { streamed.duration = imported.duration }
        if streamed.coverImageData == nil { streamed.coverImageData = imported.coverImageData }
        // The file's own chapters: they are the ones measured against the audio now on disk.
        let moving = imported.chapters
        if !moving.isEmpty {
            for chapter in streamed.chapters { context.delete(chapter) }
            for chapter in moving { chapter.audiobook = streamed }
        }
        let importedID = imported.id
        let links = try? context.fetch(
            FetchDescriptor<AudiobookShelfLinkModel>(predicate: #Predicate { $0.audiobookID == importedID })
        )
        for link in links ?? [] { context.delete(link) }
        // Not `deleteAudiobook`: that also deletes the file, which now belongs to `streamed`.
        context.delete(imported)
    }
}
