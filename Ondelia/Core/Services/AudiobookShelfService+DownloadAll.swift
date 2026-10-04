import Foundation

/// Downloading a whole series or everything by an author, from a long press on the shelf.
extension AudiobookShelfService {
    enum DownloadGroup {
        /// A server series, or a server collection, whose books came with it.
        case series(AudiobookShelfAPI.Series)
        case author(String)
    }

    /// Fetches the group's books and starts a download for each one not already on this
    /// device, downloading or importing. Each is imported when its download finishes, one at a
    /// time through the import queue, so they arrive in download order rather than series order.
    func downloadAll(_ group: DownloadGroup, library: String) async {
        var account = browsingAccount
        var library = library
        if case .series(let series) = group, let owner = self.account(forGroup: series.id) {
            account = owner
            library = AudiobookShelfCatalog.shared.library(of: owner.id) ?? library
        }
        guard let (server, token) = session(for: account) else { return }
        do {
            let items = switch group {
            case .series(let group) where group.isServerCollection:
                group.books ?? []
            case .series(let group):
                try await AudiobookShelfAPI.seriesItems(server: server, token: token, library: library, series: group.id)
            case .author(let id):
                try await AudiobookShelfAPI.authorItems(server: server, token: token, library: library, author: id)
            }
            for item in missing(from: items) { download(item) }
        } catch {
            Log.library.error("AudiobookShelf download-all failed: \(error.localizedDescription)")
            problem = Problem(
                title: NSLocalizedString("Download Failed", comment: "AudiobookShelf download error title"),
                message: error.localizedDescription
            )
        }
    }

    /// The items with nothing on this device and nothing in flight.
    func missing(from items: [AudiobookShelfAPI.Item]) -> [AudiobookShelfAPI.Item] {
        let library = libraryBooks
        return items.filter { item in
            if downloads[item.id] != nil || importing.contains(item.id) { return false }
            guard let book = library[item.id] else { return true }
            return !AudiobookManager.shared.hasFile(book)
        }
    }
}
