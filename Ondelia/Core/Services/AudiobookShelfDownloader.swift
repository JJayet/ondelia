import Foundation

/// The delegate of the background `URLSession` that AudiobookShelf downloads run on, so a book keeps
/// downloading while the app is suspended, and finishes even if the system terminates it.
///
/// Holds no state: every event is forwarded to `AudiobookShelfService` on the main actor.
/// Each task's `taskDescription` carries the AudiobookShelf item id and title — never the
/// token, since the system persists task descriptions across launches.
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

    /// "id\ntitle". The title is there so the library can name a download a previous launch
    /// started; ids never contain a newline.
    static func describe(id: String, title: String) -> String { "\(id)\n\(title)" }

    /// A task started before titles were stored has the bare id, and an empty title.
    static func parse(_ description: String?) -> (id: String, title: String)? {
        guard let description, !description.isEmpty else { return nil }
        let parts = description.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
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
        guard let id = Self.parse(downloadTask.taskDescription)?.id else { return }
        // Must happen before returning: the system deletes `location` right after.
        let result = Result {
            try AudiobookShelfAPI.keepDownload(at: location, response: downloadTask.response, item: id)
        }
        Task { @MainActor in
            AudiobookShelfService.shared.downloadFinished(id: id, result: result)
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
