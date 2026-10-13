import Foundation

/// Server books already finished stay off the shelves, Search and Collections, so what is left
/// is what there is still to listen to. Finished on the server: by this app, another one, or
/// the web client.
extension AudiobookShelfService {
    /// The listener's switch; on until they turn it off.
    static var hidesFinished: Bool {
        UserDefaults.standard.object(forKey: Defaults.hidesFinished) as? Bool ?? true
    }

    func hidesFinished(_ item: String, on serverID: String?) -> Bool {
        guard let serverID, Self.hidesFinished else { return false }
        return finishedItems[serverID]?.contains(item) == true
    }

    /// Asks each server which books are finished. A server that does not answer keeps the last
    /// answer it gave.
    func refreshFinishedItems() async {
        for account in accounts {
            guard let (server, token) = session(for: account) else { continue }
            do {
                let finished = try await AudiobookShelfAPI.finishedItems(server: server, token: token)
                if finishedItems[account.id] != finished { finishedItems[account.id] = finished }
            } catch {
                Log.library.error("AudiobookShelf: finished books unavailable: \(error.localizedDescription)")
            }
        }
    }
}
