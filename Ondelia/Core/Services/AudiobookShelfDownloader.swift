import Foundation

/// The delegate of the background `URLSession` that AudiobookShelf downloads run on, so a book keeps
/// downloading while the app is suspended, and finishes even if the system terminates it.
///
/// Holds no state: every event is forwarded to `AudiobookShelfService` on the main actor.
/// Each task's `taskDescription` carries the AudiobookShelf item id, account id and title —
/// never the token, since the system persists task descriptions across launches.
final class AudiobookShelfDownloader: NSObject, URLSessionDownloadDelegate, Sendable {
    static let sessionIdentifier = "io.jayet.Isora.audiobookshelf"

    /// Creates the session with a new downloader as its delegate. Call once per process: the
    /// system allows only one session per background identifier.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        // Relaunch the app when downloads finish while it is not running, so they get imported.
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: AudiobookShelfDownloader(), delegateQueue: nil)
    }

    /// "id\taccount\ntitle". The title is there so the library can name a download a previous
    /// launch started. The account is the one the download was asked of: the item's owner is
    /// otherwise looked up again when it finishes, by which time the browser may show another
    /// server. Ids never contain a tab or a newline.
    static func describe(id: String, account: String?, title: String) -> String {
        "\(id)\t\(account ?? "")\n\(title)"
    }

    /// A task started before titles were stored has the bare id, and an empty title; one
    /// started before accounts were stored has no account.
    static func parse(_ description: String?) -> (id: String, account: String?, title: String)? {
        guard let description, !description.isEmpty else { return nil }
        let parts = description.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let ids = parts[0].split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        let account = ids.count > 1 && !ids[1].isEmpty ? String(ids[1]) : nil
        return (String(ids[0]), account, parts.count > 1 ? String(parts[1]) : "")
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = Self.parse(downloadTask.taskDescription)?.id else { return }
        // A zip is streamed as it is built, so the server usually cannot say how big it will be.
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        Task { @MainActor in
            AudiobookShelfService.shared.downloadProgressed(id: id, received: totalBytesWritten, expected: expected)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let (id, account, _) = Self.parse(downloadTask.taskDescription) else { return }
        // Must happen before returning: the system deletes `location` right after.
        let result = Result {
            try AudiobookShelfAPI.keepDownload(at: location, response: downloadTask.response, item: id)
        }
        Task { @MainActor in
            AudiobookShelfService.shared.downloadFinished(id: id, account: account, result: result)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Success already went through `didFinishDownloadingTo`.
        guard let id = Self.parse(task.taskDescription)?.id, let error else { return }
        Task { @MainActor in
            AudiobookShelfService.shared.downloadFinished(id: id, result: .failure(error))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            AudiobookShelfService.shared.finishBackgroundEvents()
        }
    }
}
