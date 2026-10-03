import Foundation

// MARK: - Streaming on the watch: its sign-in, and the books it starts by itself
extension WatchSyncService {
    private static let aliasesKey = "watchBookAliases"

    /// Hands the watch the AudiobookShelf sign-in, or tells it to forget it. Called on every
    /// activation and whenever the account or the selected server library changes.
    func sendServerAccount() {
        let shelf = AudiobookShelfService.shared
        let account = shelf.server.flatMap { server in
            shelf.token.map { ServerAccount(server: server, token: $0, library: shelf.selectedLibrary) }
        }
        // Every foreground reloads the account; only a change is worth a transfer.
        guard session?.activationState == .activated, sentServerAccount != .some(account) else { return }
        sentServerAccount = .some(account)
        send(.serverAccount(account))
    }

    /// Watch book ids that turned out to be a book the Library already held, mapped to it.
    /// Kept for good: events the watch queued under its own id can arrive any time later.
    var aliases: [UUID: UUID] {
        let stored = UserDefaults.standard.dictionary(forKey: Self.aliasesKey) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            UUID(uuidString: key).flatMap { from in UUID(uuidString: value).map { (from, $0) } }
        })
    }

    private func addAlias(from watchID: UUID, to bookID: UUID) {
        var stored = UserDefaults.standard.dictionary(forKey: Self.aliasesKey) as? [String: String] ?? [:]
        stored[watchID.uuidString] = bookID.uuidString
        UserDefaults.standard.set(stored, forKey: Self.aliasesKey)
    }

    /// The watch streamed a server audiobook under an id it made up: the audiobook joins the
    /// Library under that id, or, when the Library already links the item, the id becomes an
    /// alias of that book. The watch's events for it wait until either is done.
    func watchJoined(bookID: UUID, itemID: String) {
        let shelf = AudiobookShelfService.shared
        if let existing = shelf.libraryBooks[itemID] {
            if existing.id != bookID { addAlias(from: bookID, to: existing.id) }
            pushSnapshot()
            return
        }
        joinBuffers[bookID] = []
        Task {
            do {
                let book = try await shelf.libraryBook(itemID: itemID, id: bookID)
                if book.id != bookID { addAlias(from: bookID, to: book.id) }
                book.lastPlayed = Date()
                SwiftDataController.shared.save()
            } catch {
                // ponytail: the buffered events are dropped, listening time included. Persist the
                // join and retry at the next launch if a phone that cannot reach the server
                // while the watch can turns out to be common.
                Log.sync.error("❌ WatchSyncService: watch book did not join — \(error.localizedDescription, privacy: .public)")
            }
            let buffered = joinBuffers.removeValue(forKey: bookID) ?? []
            for event in buffered { handle(event) }
            pushSnapshot()
        }
    }
}

extension SyncEvent {
    /// The book an event from the watch is about, so it can wait for that book to join.
    var bookID: UUID? {
        switch self {
        case let .progress(bookID, _, _), let .listened(bookID, _, _), let .bookmarkAdded(bookID, _),
             let .chapterRequested(bookID, _), let .chapterDeleted(bookID, _), let .bookCleared(bookID),
             let .watchInventory(bookID, _), let .transferProgress(bookID, _, _):
            return bookID
        case .pauseOtherSide, .serverAccount, .joined:
            return nil
        }
    }
}
