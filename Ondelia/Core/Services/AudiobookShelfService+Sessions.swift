import Foundation
import SwiftData

/// Sends the listening log of linked books to the server, so its statistics count the time
/// spent here. Every session, past ones included: a book linked today brings its history.
extension AudiobookShelfService {
    /// Seconds already sent per session id. Per device: another device sending the same
    /// session again only rewrites it on the server.
    static let sentSessionsKey = "audiobookshelf.sentSessions"

    /// Sessions the server has not heard of, or that grew by a second or more since.
    static func unsent(_ sessions: [ListeningSessionModel], sent: [String: Double]) -> [ListeningSessionModel] {
        sessions.filter { $0.seconds - (sent[$0.id.uuidString.lowercased()] ?? 0) >= 1 }
    }

    /// Sends the book's unsent sessions. True when the server took their position as the
    /// item's, which then needs the book's own word on whether it is finished.
    @discardableResult
    func sendSessions(for book: AudiobookModel, item: String, server: URL, token: String) async -> Bool {
        guard SwiftDataController.shared.isLoaded else { return false }
        let id = book.id
        let logged = (try? SwiftDataController.shared.context.fetch(
            FetchDescriptor<ListeningSessionModel>(predicate: #Predicate { $0.bookID == id })
        )) ?? []
        let defaults = UserDefaults.standard
        let pending = Self.unsent(logged, sent: defaults.dictionary(forKey: Self.sentSessionsKey) as? [String: Double] ?? [:])
        guard !pending.isEmpty, book.duration > 0 else { return false }
        let position = min(max(book.currentPosition, 0), book.duration)
        let payload = pending.map {
            AudiobookShelfAPI.LocalSession($0, item: item, position: position, duration: book.duration)
        }
        let results: [AudiobookShelfAPI.LocalSessionResult]
        do {
            results = try await AudiobookShelfAPI.syncLocalSessions(server: server, token: token, sessions: payload)
        } catch {
            Log.library.error("AudiobookShelf: session sync failed: \(error.localizedDescription)")
            return false
        }
        // Read again: another send may have finished while this one was in flight.
        var sent = defaults.dictionary(forKey: Self.sentSessionsKey) as? [String: Double] ?? [:]
        let accepted = Set(results.filter(\.success).map(\.id))
        for session in payload where accepted.contains(session.id) {
            sent[session.id] = max(sent[session.id] ?? 0, session.timeListening)
        }
        defaults.set(sent, forKey: Self.sentSessionsKey)
        return results.contains { $0.progressSynced == true }
    }

    /// Catches up every linked book: past listening, and what an offline stretch or a failed
    /// request left behind. Called when the app becomes active.
    func sendAllSessions() async {
        guard Self.syncsListening else { return }
        await SwiftDataController.shared.whenLoaded()
        let context = SwiftDataController.shared.context
        for link in Self.links() {
            let bookID = link.audiobookID
            var descriptor = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == bookID })
            descriptor.fetchLimit = 1
            guard let book = (try? context.fetch(descriptor))?.first,
                  let (server, token) = session(forItem: link.itemID),
                  await sendSessions(for: book, item: link.itemID, server: server, token: token)
            else { continue }
            // Only a session newer than the server's position moves it, and the position alone
            // can unmark a finished book there: the book's own state follows.
            do {
                try await AudiobookShelfAPI.updateProgress(
                    server: server, token: token, item: link.itemID,
                    currentTime: min(max(book.currentPosition, 0), book.duration),
                    duration: book.duration, isFinished: book.isFinished
                )
            } catch {
                Log.library.error("AudiobookShelf: progress push failed: \(error.localizedDescription)")
            }
        }
    }
}
