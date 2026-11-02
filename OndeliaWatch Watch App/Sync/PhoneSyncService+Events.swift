import Foundation

/// One-shot facts pushed by the phone.
extension PhoneSyncService {
    func handle(eventData: Data) {
        guard let event = try? SyncCodec.decode(SyncEvent.self, from: eventData) else {
            Log.sync.error("❌ PhoneSyncService: event did not decode")
            return
        }
        handle(event)
    }

    func handle(_ event: SyncEvent) {
        switch event {
        case let .progress(bookID, position, at):
            applyRemoteProgress(bookID: bookID, position: position, at: at)
        case let .transferProgress(bookID, chapterNumber, fraction):
            WatchTransferState.shared.markProgress(bookID: bookID, chapter: chapterNumber, fraction: fraction)
        case let .bookCleared(bookID):
            clearBook(bookID)
        case .pauseOtherSide:
            WatchAudioManager.shared.pause()
        case let .serverAccount(account):
            WatchServerAccount.shared.apply(account)
        case let .serverAccounts(accounts):
            WatchServerAccount.shared.apply(accounts)
        case .bookmarkAdded, .chapterRequested, .chapterDeleted, .watchInventory, .listened, .joined:
            // Sent by the watch, never to it.
            break
        }
    }

    /// Last write wins, and if the listener is looking at that book on a paused watch the
    /// player is moved too, so resuming here carries on from the phone.
    private func applyRemoteProgress(bookID: UUID, position: TimeInterval, at: Date) {
        guard let book = book(bookID) else { return }
        if WatchLibraryDisk.shouldApplyRemotePosition(remote: at, local: book.positionUpdatedAt) {
            book.currentPosition = position
            book.positionUpdatedAt = at
            WatchLibraryStore.save()
        }
        // Even when the guard failed: a snapshot may already have written this position to the row.
        alignPausedPlayer(with: book)
    }

    /// A paused player keeps its own clock and `load` skips the book it already holds, so
    /// without this a resume would send the old position stamped now and beat the newer one.
    func alignPausedPlayer(with book: AudiobookModel) {
        let audio = WatchAudioManager.shared
        guard audio.currentBook?.id == book.id, !audio.player.isPlaying,
              audio.player.currentTime != book.currentPosition else { return }
        audio.seek(to: book.currentPosition, persist: false)
    }
}
