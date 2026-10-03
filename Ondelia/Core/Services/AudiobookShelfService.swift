import Foundation
import Observation
import SwiftData

/// The AudiobookShelf account and the downloads in flight.
///
/// Downloads live here rather than in the browsing view so leaving the screen does not cancel
/// them. A finished download is handed to the regular import queue, then deleted.
@MainActor
@Observable
final class AudiobookShelfService {
    static let shared = AudiobookShelfService()

    enum Defaults {
        static let server = "audiobookshelf.server"
        static let username = "audiobookshelf.username"
        static let library = "audiobookshelf.library"
    }

    private static let tokenKey = "audiobookshelf.token"

    struct DownloadProgress: Equatable {
        var title = ""
        /// Not kept across a relaunch: the task description carries the title only.
        var author: String?
        var received: Int64 = 0
        /// Nil when the server did not say, which is the usual case for a zipped folder.
        var expected: Int64?

        var fraction: Double? {
            guard let expected, expected > 0 else { return nil }
            return min(Double(received) / Double(expected), 1)
        }
    }

    /// Items being downloaded, by AudiobookShelf id.
    private(set) var downloads: [String: DownloadProgress] = [:]
    /// Items downloaded and waiting for, or going through, their import; after that,
    /// `libraryBooks` knows them.
    private(set) var importing: Set<String> = []
    struct Problem: Equatable {
        let title: String
        let message: String
    }

    /// The last download or streaming failure, for the shelf to show.
    var problem: Problem?

    /// Mirrors of the keychain and defaults, so views observing `isSignedIn` update. Another
    /// device's sign-in arrives through iCloud Keychain and `SettingsSync`; `reload` picks it up.
    private(set) var token: String?
    private(set) var server: URL?
    private(set) var username: String?

    /// What was last pushed per book, and the pushes in flight. In memory only: forgetting them
    /// costs one redundant request after a launch.
    var pushedProgress: [UUID: PushedProgress] = [:]
    var pushingProgress: Set<UUID> = []
    /// Items whose library entry is being made for streaming.
    var preparingStreams: Set<String> = []

    /// Created at launch, not on first use: a relaunch for finished background downloads only
    /// delivers them once a session with the same identifier exists again.
    private let session = AudiobookShelfDownloader.makeSession()
    /// Handed over by the system when it relaunches the app for this session's events.
    var backgroundCompletion: (() -> Void)?

    private init() {
        reload()
        // Downloads that finished but whose import a previous launch did not get to finish.
        // The import skips a file the library already holds, so a book imported just before
        // the app was killed is not added twice.
        for pending in AudiobookShelfAPI.pendingDownloads() {
            Log.library.debug("AudiobookShelf: importing a download left by the previous launch")
            importDownload(pending.file, item: pending.item)
        }

        // Downloads still running from a previous launch: show them again.
        session.getAllTasks { tasks in
            let running = tasks.compactMap { task -> (String, DownloadProgress)? in
                guard task.state == .running || task.state == .suspended,
                      let (id, title) = AudiobookShelfDownloader.parse(task.taskDescription)
                else { return nil }
                let expected = task.countOfBytesExpectedToReceive
                return (id, DownloadProgress(
                    title: title,
                    received: task.countOfBytesReceived,
                    expected: expected > 0 ? expected : nil
                ))
            }
            Task { @MainActor in
                for (id, progress) in running where AudiobookShelfService.shared.downloads[id] == nil {
                    AudiobookShelfService.shared.downloads[id] = progress
                }
            }
        }
    }

    func reload() {
        token = Keychain.get(Self.tokenKey)
        server = UserDefaults.standard.string(forKey: Defaults.server).flatMap(URL.init(string:))
        username = UserDefaults.standard.string(forKey: Defaults.username)
    }

    /// Whether the account is shared with the user's other devices: the same switch as the
    /// library and settings.
    private var syncsAccount: Bool { SwiftDataController.isICloudSyncEnabled }
    var isSignedIn: Bool { token != nil && server != nil }

    var selectedLibrary: String? {
        get { UserDefaults.standard.string(forKey: Defaults.library) }
        set {
            UserDefaults.standard.set(newValue, forKey: Defaults.library)
            WatchSyncService.shared.sendServerAccount()
        }
    }

    func signIn(server input: String, username: String, password: String) async throws {
        guard let server = AudiobookShelfAPI.serverURL(from: input) else {
            throw AudiobookShelfAPI.Failure.invalidServer
        }
        let token = try await AudiobookShelfAPI.signIn(server: server, username: username, password: password)
        Keychain.set(token, for: Self.tokenKey, synchronizable: syncsAccount)
        UserDefaults.standard.set(server.absoluteString, forKey: Defaults.server)
        UserDefaults.standard.set(username, forKey: Defaults.username)
        reload()
        WatchSyncService.shared.sendServerAccount()
    }

    /// Forgets the account — on every device when it is synced, since the token lives in
    /// iCloud Keychain. The server keeps the token, which is the legacy per-user API token and
    /// not one this app created, so there is nothing to revoke.
    func signOut() {
        Keychain.set(nil, for: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Defaults.library)
        reload()
        WatchSyncService.shared.sendServerAccount()
        AudiobookShelfCatalog.shared.forget()
        AudiobookShelfImages.forget()
    }

    func download(_ item: AudiobookShelfAPI.Item) {
        download(id: item.id, title: item.title, author: item.author)
    }

    func download(id: String, title: String, author: String?) {
        guard let server, let token, downloads[id] == nil, !importing.contains(id) else { return }
        let task = session.downloadTask(
            with: AudiobookShelfAPI.downloadRequest(server: server, token: token, item: id)
        )
        task.taskDescription = AudiobookShelfDownloader.describe(id: id, title: title)
        downloads[id] = DownloadProgress(title: title, author: author)
        task.resume()
    }

    func cancelDownload(id: String) {
        session.getAllTasks { tasks in
            tasks.first { AudiobookShelfDownloader.parse($0.taskDescription)?.id == id }?.cancel()
        }
        downloads[id] = nil
    }

    func downloadProgressed(id: String, received: Int64, expected: Int64?) {
        // Dropped once finished or cancelled: a late progress event must not bring the row back.
        guard let current = downloads[id] else { return }
        var next = current
        next.received = received
        next.expected = expected
        // Progress fires for every chunk; redraw at most once per percent (or MB when unsized).
        let step: Int64 = expected.map { max($0 / 100, 1) } ?? 1_000_000
        guard next.received / step != current.received / step || next.expected != current.expected else { return }
        downloads[id] = next
    }

    func downloadFinished(id: String, result: Result<URL, any Error>) {
        let finished = downloads.removeValue(forKey: id)
        switch result {
        case .success(let file):
            importDownload(file, item: id, title: finished?.title, author: finished?.author)
        case .failure(let error as URLError) where error.code == .cancelled:
            break
        case .failure(let error):
            Log.library.error("AudiobookShelf download failed: \(error.localizedDescription)")
            problem = Problem(
                title: NSLocalizedString("Download Failed", comment: "AudiobookShelf download error title"),
                message: error.localizedDescription
            )
        }
    }

    /// Queues the import and deletes the download's folder once it has run, whatever the
    /// outcome: a file the importer rejected would be rejected again at every launch.
    ///
    /// The server's title and author replace what the files say: AudiobookShelf is where the
    /// reader curates them, and a file without tags is otherwise named after its folder.
    private func importDownload(_ file: URL, item: String, title: String? = nil, author: String? = nil) {
        let folder = file.deletingLastPathComponent()
        importing.insert(item)
        AudiobookManager.shared.handleImportRequest(urls: [file]) {
            try? FileManager.default.removeItem(at: folder)
        } onImported: { imported in
            let context = SwiftDataController.shared.context
            var books = imported
            // A book already streamed keeps its entry, and with it the listener's position.
            if books.count == 1, let book = books.first,
               let streamed = self.libraryBooks[item], streamed.id != book.id,
               !AudiobookManager.shared.hasFile(streamed) {
                Self.adopt(book, into: streamed, context: context)
                books = [streamed]
            }
            // Remembered on the book, so the browser can say it is in the library on every
            // device and after a relaunch.
            let linked = Set(Self.links().filter { $0.itemID == item }.map(\.audiobookID))
            for book in books where !linked.contains(book.id) {
                context.insert(AudiobookShelfLinkModel(audiobookID: book.id, itemID: item))
            }
            // One book per item is the normal case. An item the importer split into several
            // books keeps their own titles rather than all taking the item's.
            if books.count == 1, let book = books.first {
                if let title, !title.isEmpty { book.title = title }
                if let author, !author.isEmpty { book.author = author }
            }
            SwiftDataController.shared.save()
            self.linksDidChange()
            self.importing.remove(item)
            AudiobookManager.shared.fetchAudiobooks()
        }
    }

    /// Also called by every library fetch: `libraryBooks` is memoised on this version, and a
    /// fetch can drop a linked book (merged away, deleted on another device).
    func linksDidChange() { linksVersion += 1 }

    /// Bumped whenever links are written: a SwiftData fetch is not observable, so views reading
    /// `libraryBooks` would otherwise miss the link a finished import adds.
    private var linksVersion = 0

    private static func links() -> [AudiobookShelfLinkModel] {
        guard SwiftDataController.shared.isLoaded else { return [] }
        return (try? SwiftDataController.shared.context.fetch(FetchDescriptor<AudiobookShelfLinkModel>())) ?? []
    }

    /// Library books by the AudiobookShelf item they were downloaded from. A link whose book
    /// was merged away or deleted on another device is ignored rather than trusted.
    ///
    /// Memoised per `linksVersion`: the Library screen reads it several times per redraw, and
    /// each read used to fetch every link.
    var libraryBooks: [String: AudiobookModel] {
        let version = linksVersion
        if let cached = libraryBooksCache, cached.version == version { return cached.books }
        let books = Dictionary(AudiobookManager.shared.audiobooks.map { ($0.id, $0) }) { first, _ in first }
        var byItem: [String: AudiobookModel] = [:]
        for link in Self.links() {
            if let book = books[link.audiobookID] { byItem[link.itemID] = book }
        }
        libraryBooksCache = (version, byItem)
        return byItem
    }

    @ObservationIgnored private var libraryBooksCache: (version: Int, books: [String: AudiobookModel])?

    func finishBackgroundEvents() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}
