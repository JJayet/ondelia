import AVFoundation
import Foundation
import SwiftData

enum WatchPlaybackState: Equatable {
    case idle
    case playing
    case paused
}

/// The watch's playback. Deliberately thin: one `AudiobookPlayer`, the progress writes the sync
/// rules need, and the timer/speed/bookmark bits the player screen offers. The iPhone's
/// `GlobalAudioManager` is not mirrored here — none of what it coordinates exists on the watch.
@MainActor
@Observable
final class WatchAudioManager {
    static let shared = WatchAudioManager()

    let player = AudiobookPlayer()

    private(set) var currentBook: AudiobookModel?
    /// True once activating the audio session failed, which on this platform means "no
    /// Bluetooth route": the view turns it into "Connect AirPods".
    private(set) var needsHeadphones = false
    /// Set when playback stopped at a chapter this watch has not been sent yet.
    private(set) var waitingForChapter: Int?
    /// The book plays from the server rather than from chapter files on the watch.
    private(set) var isStreaming = false

    var sleepTimer: SleepTimerOption = .off
    private(set) var sleepTimeRemaining: TimeInterval?

    /// The speeds the picker offers, and the only ones ever stored.
    static let speeds: [Float] = [0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0]

    var playbackState: WatchPlaybackState {
        guard currentBook != nil else { return .idle }
        return player.isPlaying ? .playing : .paused
    }

    // Ticker bookkeeping, driven from `WatchAudioManager+Progress`.
    var ticker: Task<Void, Never>?
    var secondsSincePersist = 0
    /// Real seconds played since the phone was last told, for its listening log.
    var listenedSecondsUnsent = 0
    var lastChapterNumber: Int?
    var remoteCommandsInstalled = false

    private init() {}

    // MARK: - Loading

    func load(_ book: AudiobookModel) async {
        guard currentBook?.id != book.id else { return }
        persistProgress()
        stopTicker()
        // The previous book's tracks go before the switch: a failed load would otherwise play
        // them under this book and write their position into it.
        player.tearDown()
        currentBook = book
        waitingForChapter = nil
        lastChapterNumber = nil
        installCallbacks()
        guard await loadTracks(for: book) else {
            Log.audio.error("❌ WatchAudioManager: nothing playable for this book")
            // Not current, so asking for it again tries again.
            currentBook = nil
            updateNowPlaying()
            return
        }
        player.setPlaybackRate(book.speed)
        player.seek(to: book.currentPosition)
        book.lastPlayed = Date()
        updateNowPlaying()
    }

    /// Loads if needed, then plays.
    func loadAndPlay(_ book: AudiobookModel) async {
        await load(book)
        await startPlayback()
    }

    /// The chapter files when the one at the position is here, the server when it is not and
    /// the book is linked, and the files again, as before streaming, when neither works.
    private func loadTracks(for book: AudiobookModel) async -> Bool {
        isStreaming = false
        let onDisk = PhoneSyncService.shared.chaptersOnDisk(bookID: book.id)
        let isHere = book.currentChapterNumber.map(onDisk.contains) ?? false
        if !isHere, let tracks = await WatchServerAccount.shared.streamTracks(for: book), player.load(tracks: tracks) {
            isStreaming = true
            return true
        }
        return await player.load(book)
    }

    /// Carries on from `position` over the network: the next chapter is not on the watch.
    /// False when the server cannot be reached, which leaves waiting for the phone.
    func continueStreaming(_ book: AudiobookModel, from position: TimeInterval) async -> Bool {
        guard currentBook?.id == book.id,
              let tracks = await WatchServerAccount.shared.streamTracks(for: book),
              player.load(tracks: tracks) else { return false }
        isStreaming = true
        player.setPlaybackRate(book.speed)
        player.seek(to: position)
        await startPlayback()
        return true
    }

    private func installCallbacks() {
        player.onTrackEnded = { [weak self] index in self?.handleTrackEnded(index) }
        player.onPlaybackEnded = { [weak self] in self?.handlePlaybackEnded() }
        player.onPlaybackFailed = { [weak self] in self?.handlePlaybackEnded() }
    }

    // MARK: - Transport

    func play() {
        Task { await startPlayback() }
    }

    func startPlayback() async {
        guard currentBook != nil, !player.tracks.isEmpty else { return }
        let wasPlaying = player.isPlaying
        guard await activateAudioSession() else { return }
        // Whichever side starts, the other one stops: the pause produces a progress write that
        // lands before this side's first tick. Only on the edge — a chapter jump made while
        // already playing comes through here too and has nothing to announce.
        if !wasPlaying {
            PhoneSyncService.shared.send(SyncEvent.pauseOtherSide, urgent: true)
        }
        waitingForChapter = nil
        player.play()
        startTicker()
        updateNowPlaying()
    }

    func pause() {
        guard player.isPlaying else { return }
        player.pause()
        persistProgress()
        updateNowPlaying()
    }

    func toggle() {
        if player.isPlaying { pause() } else { play() }
    }

    func skipForward() {
        seek(to: player.currentTime + PhoneSyncService.shared.skipForwardSeconds)
    }

    func skipBackward() {
        seek(to: player.currentTime - PhoneSyncService.shared.skipBackSeconds)
    }

    func seek(to time: TimeInterval, persist: Bool = true) {
        player.seek(to: time)
        if persist { persistProgress() }
        updateNowPlaying()
    }

    func playChapter(number: Int) {
        guard let book = currentBook,
              let chapter = book.sortedChapters.first(where: { Int($0.chapterNumber) == number }) else { return }
        seek(to: chapter.startTime)
        play()
    }

    func setRate(_ rate: Float) {
        player.setPlaybackRate(rate)
        currentBook?.speed = rate
        WatchLibraryStore.save()
        updateNowPlaying()
    }

    func stop() {
        persistProgress()
        stopTicker()
        player.tearDown()
        currentBook = nil
        isStreaming = false
        waitingForChapter = nil
        sleepTimer = .off
        sleepTimeRemaining = nil
        updateNowPlaying()
    }

    func unloadIfPlaying(bookID: UUID) {
        guard currentBook?.id == bookID else { return }
        stop()
    }

    private func handlePlaybackEnded() {
        stopTicker()
        persistProgress()
        updateNowPlaying()
    }

    // MARK: - Internal setters used by the extensions

    func setWaitingForChapter(_ number: Int?) {
        waitingForChapter = number
    }

    func setNeedsHeadphones(_ value: Bool) {
        needsHeadphones = value
    }

    func setSleepTimeRemaining(_ value: TimeInterval?) {
        sleepTimeRemaining = value
    }
}
