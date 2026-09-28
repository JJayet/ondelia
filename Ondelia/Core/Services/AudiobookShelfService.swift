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
    /// Items downloaded and queued for import this session, so the row can say so before the
    /// import has finished; after that, `itemsInLibrary` knows.
    private(set) var downloaded: Set<String> = []
    /// The last download failure, for the browsing view to show.
    var downloadError: String?

    /// Mirrors of the keychain and defaults, so views observing `isSignedIn` update. Another
    /// device's sign-in arrives through iCloud Keychain and `SettingsSync`; `reload` picks it up.
    private(set) var token: String?
    private(set) var server: URL?
    private(set) var username: String?

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
        set { UserDefaults.standard.set(newValue, forKey: Defaults.library) }
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
    }

    /// Forgets the account — on every device when it is synced, since the token lives in
    /// iCloud Keychain. The server keeps the token, which is the legacy per-user API token and
    /// not one this app created, so there is nothing to revoke.
    func signOut() {
        Keychain.set(nil, for: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Defaults.library)
        reload()
    }

    func download(_ item: AudiobookShelfAPI.Item) {
        guard let server, let token, downloads[item.id] == nil else { return }
        let task = session.downloadTask(
            with: AudiobookShelfAPI.downloadRequest(server: server, token: token, item: item.id)
        )
        task.taskDescription = AudiobookShelfDownloader.describe(id: item.id, title: item.title)
        downloads[item.id] = DownloadProgress(title: item.title)
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
        downloads[id] = nil
        switch result {
        case .success(let file):
            importDownload(file, item: id)
            downloaded.insert(id)
        case .failure(let error as URLError) where error.code == .cancelled:
            break
        case .failure(let error):
            Log.library.error("AudiobookShelf download failed: \(error.localizedDescription)")
            downloadError = error.localizedDescription
        }
    }

    /// Queues the import and deletes the download's folder once it has run, whatever the
    /// outcome: a file the importer rejected would be rejected again at every launch.
    private func importDownload(_ file: URL, item: String) {
        let folder = file.deletingLastPathComponent()
        AudiobookManager.shared.handleImportRequest(urls: [file]) {
            try? FileManager.default.removeItem(at: folder)
        } onImported: { books in
            // Remembered on the book, so the browser can say it is in the library on every
            // device and after a relaunch.
            let context = SwiftDataController.shared.context
            let linked = Set(Self.links().filter { $0.itemID == item }.map(\.audiobookID))
            for book in books where !linked.contains(book.id) {
                context.insert(AudiobookShelfLinkModel(audiobookID: book.id, itemID: item))
            }
            SwiftDataController.shared.save()
        }
    }

    private static func links() -> [AudiobookShelfLinkModel] {
        guard SwiftDataController.shared.isLoaded else { return [] }
        return (try? SwiftDataController.shared.context.fetch(FetchDescriptor<AudiobookShelfLinkModel>())) ?? []
    }

    /// Items some book still in the library was downloaded from. A link whose book was merged
    /// away or deleted on another device is ignored rather than trusted.
    var itemsInLibrary: Set<String> {
        let books = Set(AudiobookManager.shared.audiobooks.map(\.id))
        return Set(Self.links().filter { books.contains($0.audiobookID) }.map(\.itemID))
    }

    func finishBackgroundEvents() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }
}
