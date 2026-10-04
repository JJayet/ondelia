import Foundation

// MARK: - Incoming events, incoming commands, outgoing progress
extension WatchSyncService {
    /// A playing book writes its position every five seconds; the watch does not need to hear
    /// about all of them. Pause and stop flush regardless.
    private static let progressInterval: TimeInterval = 30

    func handle(_ event: SyncEvent) {
        if let bookID = event.bookID, joinBuffers[bookID] != nil {
            joinBuffers[bookID]?.append(event)
            return
        }
        switch event {
        case let .progress(bookID, position, at):
            applyRemoteProgress(bookID: bookID, position: position, at: at)
        case let .listened(bookID, seconds, at):
            guard let book = book(bookID) else { break }
            ReadingStatistics.shared.addListeningTime(seconds, for: book, at: at)
        case let .bookmarkAdded(bookID, bookmark):
            applyRemoteBookmark(bookID: bookID, bookmark: bookmark)
        case let .chapterRequested(bookID, chapterNumber):
            requestedChapter(bookID: bookID, chapterNumber: chapterNumber)
        case let .chapterDeleted(bookID, chapterNumber):
            markOnWatch(bookID: bookID, chapterNumber: chapterNumber, present: false)
        case let .bookCleared(bookID):
            WatchTransferQueue.shared.clear(bookID: bookID)
            setInventory(bookID: bookID, chapters: [])
        case let .watchInventory(bookID, chapterNumbers):
            setInventory(bookID: bookID, chapters: Set(chapterNumbers))
        case .transferProgress:
            // The phone is the sender here; it already knows.
            break
        case .pauseOtherSide:
            guard GlobalAudioManager.shared.isPlaying() else { return }
            GlobalAudioManager.shared.pausePlayback()
        case let .joined(bookID, itemID, serverID):
            watchJoined(bookID: bookID, itemID: itemID, serverID: serverID)
        case .serverAccount, .serverAccounts:
            // Sent by the phone, never to it.
            break
        }
    }

    func perform(_ command: RemoteCommand) async {
        let audio = GlobalAudioManager.shared
        switch command {
        case let .play(bookID):
            guard let book = book(bookID) else { break }
            PlaybackCommands.play(book)
        case .toggle:
            await PlaybackCommands.perform(.toggle)
        case .pause:
            audio.pausePlayback()
        case let .skipForward(interval):
            guard await PlaybackCommands.loadedBook() != nil else { break }
            audio.skipForward(interval)
        case let .skipBackward(interval):
            guard await PlaybackCommands.loadedBook() != nil else { break }
            audio.skipBackward(interval)
        case let .seek(position):
            guard await PlaybackCommands.loadedBook() != nil else { break }
            audio.seek(to: position)
        case let .setRate(rate):
            guard await PlaybackCommands.loadedBook() != nil else { break }
            audio.setPlaybackRate(rate)
        case let .playChapter(bookID, chapterNumber):
            playChapter(bookID: bookID, chapterNumber: chapterNumber)
        }
        pushSnapshot(immediate: true)
    }

    // MARK: - Applying what the watch sent

    private func applyRemoteProgress(bookID: UUID, position: TimeInterval, at: Date) {
        guard let book = book(bookID) else { return }
        ListenerState.shared.apply(.position(position), to: book, from: .watch, at: at)
    }

    private func applyRemoteBookmark(bookID: UUID, bookmark: BookmarkSummary) {
        guard let book = book(bookID),
              !book.bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
        AudiobookManager.shared.createBookmark(
            for: book,
            at: bookmark.timestamp,
            title: bookmark.title ?? String(localized: "Bookmark")
        )
    }

    private func requestedChapter(bookID: UUID, chapterNumber: Int) {
        guard let book = book(bookID) else { return }
        enqueueWindow(bookID: bookID, around: chapterNumber, chapterCount: book.sortedChapters.count)
    }

    private func playChapter(bookID: UUID, chapterNumber: Int) {
        guard let book = book(bookID),
              let chapter = book.sortedChapters.first(where: { Int($0.chapterNumber) == chapterNumber })
        else { return }
        let audio = GlobalAudioManager.shared
        audio.loadAudiobook(book)
        audio.seek(to: chapter.startTime)
        audio.startPlayback()
    }

    // MARK: - Hooks the managers call

    /// The player's tick just wrote a position; see `ListenerState.Outbound.watch`.
    func phoneDidPersistProgress(for book: AudiobookModel) {
        guard Date().timeIntervalSince(lastProgressSentAt) >= Self.progressInterval else { return }
        flushProgress(for: book)
        pushSnapshot()
    }

    /// `GlobalAudioManager.playbackStateDidChange`: the phone started, paused or stopped.
    func phonePlaybackStateDidChange() {
        let audio = GlobalAudioManager.shared
        let isPlaying = audio.playbackState == .playing
        defer {
            wasPlaying = isPlaying
            pushSnapshot()
        }
        guard isPlaying else {
            // A pause or a stop is worth telling the watch about straight away.
            guard let book = audio.currentAudiobook else { return }
            flushProgress(for: book)
            return
        }
        // Only on the edge: seeks, skips and speed changes all land here while playing.
        guard !wasPlaying else { return }
        send(.pauseOtherSide, urgent: true)
    }

    private func flushProgress(for book: AudiobookModel) {
        lastProgressSentAt = Date()
        send(.progress(
            bookID: book.id,
            position: book.currentPosition,
            at: book.positionUpdatedAt ?? Date()
        ))
    }
}
