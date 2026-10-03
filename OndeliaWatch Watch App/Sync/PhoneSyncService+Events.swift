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
        case .bookmarkAdded, .chapterRequested, .chapterDeleted, .watchInventory, .listened, .joined:
            // Sent by the watch, never to it.
            break
        }
    }

    /// Last write wins, and if the listener is looking at that book on a paused watch the
    /// player is moved too, so resuming here carries on from the phone.
    private func applyRemoteProgress(bookID: UUID, position: TimeInterval, at: Date) {
        guard let book = book(bookID),
              WatchLibraryDisk.shouldApplyRemotePosition(remote: at, local: book.positionUpdatedAt) else { return }
        book.currentPosition = position
        book.positionUpdatedAt = at
        WatchLibraryStore.save()

        let audio = WatchAudioManager.shared
        guard audio.currentBook?.id == bookID, !audio.player.isPlaying else { return }
        audio.seek(to: position, persist: false)
    }
}
