import Foundation

/// Progress persistence, chapter bookkeeping and the sleep timer — everything driven by the
/// one-second ticker.
extension WatchAudioManager {
    /// Seconds between progress writes while playing. Also how often Now Playing is refreshed.
    private static let persistInterval = 30

    var currentChapter: ChapterModel? {
        chapter(containing: player.currentTime)
    }

    func chapter(containing time: TimeInterval) -> ChapterModel? {
        guard let book = currentBook else { return nil }
        let chapters = book.sortedChapters
        return chapters.first { time >= $0.startTime && time < $0.endTime } ?? chapters.last
    }

    // MARK: - Ticker

    func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard player.isPlaying else {
            stopTicker()
            return
        }
        noticeChapterChange()
        advanceSleepTimer()
        secondsSincePersist += 1
        listenedSecondsUnsent += 1
        guard secondsSincePersist >= Self.persistInterval else { return }
        secondsSincePersist = 0
        persistProgress()
        updateNowPlaying()
    }

    // MARK: - Progress

    func persistProgress() {
        guard let book = currentBook else { return }
        let position = player.currentTime
        let now = Date()
        book.currentPosition = position
        book.positionUpdatedAt = now
        book.lastPlayed = now
        WatchLibraryStore.save()
        PhoneSyncService.shared.send(SyncEvent.progress(bookID: book.id, position: position, at: now))
        guard listenedSecondsUnsent > 0 else { return }
        PhoneSyncService.shared.send(SyncEvent.listened(bookID: book.id, seconds: TimeInterval(listenedSecondsUnsent), at: now))
        listenedSecondsUnsent = 0
    }

    // MARK: - Chapters

    /// A new chapter started: keep the rolling window full by asking for chapter *n + 2*.
    private func noticeChapterChange() {
        guard let number = currentChapter.map({ Int($0.chapterNumber) }), number != lastChapterNumber else { return }
        lastChapterNumber = number
        prefetch(after: number)
    }

    private func prefetch(after number: Int) {
        guard let book = currentBook, !isStreaming else { return }
        let target = number + 2
        guard book.sortedChapters.contains(where: { Int($0.chapterNumber) == target }) else { return }
        guard !PhoneSyncService.shared.chaptersOnDisk(bookID: book.id).contains(target),
              !WatchTransferState.shared.hasRequest(bookID: book.id, chapter: target) else { return }
        PhoneSyncService.shared.requestChapter(bookID: book.id, number: target)
    }

    /// The queue moves on by itself, so a chapter the watch has not been sent would be silently
    /// skipped. Stop there instead and ask for it.
    func handleTrackEnded(_ trackIndex: Int) {
        // A streamed book's tracks are the server's files, and the queue already holds them all.
        guard let book = currentBook, !isStreaming, player.tracks.indices.contains(trackIndex) else { return }
        let boundary = player.tracks[trackIndex].end
        evictFinishedChapter(before: boundary, in: book)

        guard let next = chapter(containing: boundary + 0.5), next.endTime > boundary else { return }
        let number = Int(next.chapterNumber)
        guard !PhoneSyncService.shared.chaptersOnDisk(bookID: book.id).contains(number) else {
            prefetch(after: number)
            return
        }
        player.pause()
        stopTicker()
        // `AVQueuePlayer` has already advanced past the gap to the next file it *does* hold, so
        // the position has to be pinned back to where the listener actually stopped.
        player.seek(to: boundary)
        persistProgress()
        guard WatchServerAccount.shared.canStream(book) else {
            waitForChapter(number, of: book)
            return
        }
        Task {
            guard await continueStreaming(book, from: boundary) == false else { return }
            waitForChapter(number, of: book)
        }
    }

    private func waitForChapter(_ number: Int, of book: AudiobookModel) {
        setWaitingForChapter(number)
        PhoneSyncService.shared.requestChapter(bookID: book.id, number: number)
        updateNowPlaying()
    }

    /// Called by the sync service once a chapter file has landed.
    func chapterArrived(bookID: UUID, number: Int) async {
        guard let book = currentBook, book.id == bookID, waitingForChapter == number else { return }
        // The start of the chapter that was missing — not `player.currentTime`, which the queue
        // may have carried somewhere else while the file was on its way.
        let position = book.sortedChapters
            .first { Int($0.chapterNumber) == number }?.startTime ?? player.currentTime
        setWaitingForChapter(nil)
        // The timeline is read from the manifest, so it has to be rebuilt to see the new file.
        guard await player.load(book) else { return }
        player.setPlaybackRate(book.speed)
        player.seek(to: position)
        await startPlayback()
    }

    /// Auto eviction: the listener finished that chapter *here*, so its audio is dead weight.
    private func evictFinishedChapter(before boundary: TimeInterval, in book: AudiobookModel) {
        guard let finished = chapter(containing: boundary - 0.5) else { return }
        // The player's clock, not the stored one: `currentPosition` is only written every thirty
        // seconds, so it is almost always short of the boundary just crossed.
        guard player.currentTime >= finished.endTime - 1 else { return }
        let number = Int(finished.chapterNumber)
        guard PhoneSyncService.shared.chaptersOnDisk(bookID: book.id).contains(number) else { return }
        PhoneSyncService.shared.deleteChapter(bookID: book.id, number: number)
    }

    // MARK: - Bookmarks

    func addBookmark() {
        guard let book = currentBook else { return }
        let time = player.currentTime
        let bookmark = BookmarkModel(
            title: String(localized: "Bookmark at \(time.clockFormatted)"),
            timestamp: time,
            dateCreated: Date()
        )
        let context = WatchLibraryStore.shared.context
        context.insert(bookmark)
        book.bookmarks.append(bookmark)
        WatchLibraryStore.save()
        PhoneSyncService.shared.send(
            SyncEvent.bookmarkAdded(
                bookID: book.id,
                bookmark: BookmarkSummary(
                    id: bookmark.id,
                    timestamp: time,
                    title: bookmark.title,
                    dateCreated: bookmark.dateCreated
                )
            )
        )
    }

    // MARK: - Sleep timer

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimer = option
        player.setVolume(1)
        switch option {
        case .off:
            setSleepTimeRemaining(nil)
        case .minutes(let minutes):
            setSleepTimeRemaining(TimeInterval(minutes * 60))
        case .endOfChapter:
            setSleepTimeRemaining(currentChapter.map { max($0.endTime - player.currentTime, 0) })
        }
    }

    /// Counts down only while playing, and fades the last ten seconds so the listener is not
    /// cut off mid-word.
    private func advanceSleepTimer() {
        guard sleepTimer != .off else { return }
        if case .endOfChapter = sleepTimer {
            setSleepTimeRemaining(currentChapter.map { max($0.endTime - player.currentTime, 0) })
        } else if let remaining = sleepTimeRemaining {
            setSleepTimeRemaining(max(remaining - 1, 0))
        }
        guard let remaining = sleepTimeRemaining else { return }
        if remaining <= 10 {
            player.setVolume(Float(max(remaining, 0) / 10))
        }
        guard remaining <= 0 else { return }
        pause()
        player.setVolume(1)
        sleepTimer = .off
        setSleepTimeRemaining(nil)
    }
}
