import Foundation
import SwiftUI
import MediaPlayer

@MainActor
@Observable
final class GlobalAudioManager {
    static let shared = GlobalAudioManager()

    var currentAudiobook: AudiobookModel?
    /// The one player. Nil until a book is loaded.
    var player: AudiobookPlayer?
    var isLoading = false
    var isReady = false
    var playbackState: PlaybackState = .stopped
    var sleepTimeRemaining: TimeInterval = 0
    /// The book last counted towards `booksCompleted`, so finishing it counts once.
    var completionCountedBookID: UUID?

    /// Derived rather than assigned. As a stored flag it drifted: `stopPlayback` cleared it,
    /// but the tab accessory keyed off `currentAudiobook`, so the mini player stayed up.
    var showMiniPlayer: Bool { currentAudiobook != nil && playbackState != .stopped }

    var sleepTimer: Timer?
    /// Position in the book an "end of chapter" timer is counting towards. Nil for a plain
    /// timed sleep, which counts wall-clock seconds instead.
    var sleepChapterEnd: TimeInterval?
    /// Writes the playback position to the library while a book plays. See `+Progress`.
    var progressTimer: Timer?
    var pendingAutoplay = false
    /// Where a transport request wants the book, when it arrived before the player existed.
    /// Cleared by the load that honours it. See `loadAudiobook` and `seek`.
    var pendingSeek: TimeInterval?
    var delayedStartTask: Task<Void, Never>?
    var loadTask: Task<Void, Never>?
    /// Where the last sizeable seek started, while the player still offers to go back. See `+UndoSeek`.
    var undoSeekOrigin: TimeInterval?
    var undoSeekTask: Task<Void, Never>?

    // Session and remote controls are process-wide; see `+AudioSession` and `+RemoteCommands`.
    var hasActivatedAudioSession = false
    var wasPlayingBeforeInterruption = false
    var sessionObservers: [any NSObjectProtocol] = []
    /// `addTarget` hands back an opaque token, so `Any` is what there is to keep.
    var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []

    enum PlaybackState {
        case stopped
        case loading
        case playing
        case paused
        case failed
    }

    private init() {
        observeAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Loading

    func loadAudiobook(_ audiobook: AudiobookModel) {
        // Do not start a second load for the same book while its player is being prepared.
        if let current = currentAudiobook, current.id == audiobook.id, isLoading || player != nil {
            Log.audio.debug("🎵 GlobalAudioManager: Already loaded \(audiobook.title ?? "Unknown")")
            if !isLoading {
                playbackState = isPlaying() ? .playing : .paused
            }
            return
        }

        Log.audio.debug("🎵 GlobalAudioManager: Loading \(audiobook.title ?? "Unknown")")

        if currentAudiobook != nil, player != nil {
            persistProgress()
        }

        // A newer request supersedes whatever is still loading, which is what used to need a
        // request-ID comparison inside the completion.
        cancelDelayedStart()
        loadTask?.cancel()
        teardownPlayer()
        clearUndoSeek()

        currentAudiobook = audiobook
        isLoading = true
        isReady = false
        playbackState = .loading
        pendingAutoplay = false
        pendingSeek = nil

        activateAudioSession()

        loadTask = Task { [weak self] in
            guard let self else { return }
            let newPlayer = AudiobookPlayer()
            let loaded = await newPlayer.load(audiobook)
            guard !Task.isCancelled else {
                newPlayer.tearDown()
                return
            }
            self.finishLoad(newPlayer, loaded: loaded, for: audiobook)
        }
    }

    private func finishLoad(_ newPlayer: AudiobookPlayer, loaded: Bool, for audiobook: AudiobookModel) {
        guard loaded else {
            newPlayer.tearDown()
            isLoading = false
            playbackState = .failed
            publishPlaybackSnapshot()
            return
        }

        newPlayer.onPlaybackEnded = { [weak self] in
            self?.handlePlaybackEnded()
        }
        newPlayer.onPlaybackFailed = { [weak self] in
            self?.handlePlaybackFailed()
        }
        player = newPlayer

        // A chapter or bookmark chosen while this book was still loading wins over the saved
        // position: it is the newer request of the two.
        if let target = pendingSeek {
            newPlayer.seek(to: target)
        } else if audiobook.currentPosition > 0 {
            newPlayer.seek(to: audiobook.currentPosition)
        }
        pendingSeek = nil
        applyStoredSpeed(for: audiobook)

        isLoading = false
        isReady = true
        playbackState = .paused
        setupNowPlayingInfo(for: audiobook)
        updateNowPlayingInfo()
        startPendingPlaybackIfNeeded()
        publishPlaybackSnapshot(reloadTimeline: true)
    }

    private func startPendingPlaybackIfNeeded() {
        guard pendingAutoplay else { return }
        pendingAutoplay = false
        resumePlayback()
    }

    private func handlePlaybackEnded() {
        Log.audio.debug("✅ GlobalAudioManager: Reached the end of the book")
        playbackState = .paused
        if let audiobook = currentAudiobook {
            AudiobookManager.shared.markAsFinished(audiobook)
        }
        playbackStateDidChange()

        // Roll into the next stacked book, the way a playlist does. `startPlaybackAfterOpeningBook`
        // plays as soon as the load finishes, via `pendingAutoplay`.
        if let next = PlayQueue.shared.popNext(from: AudiobookManager.shared.audiobooks) {
            loadAudiobook(next)
            startPlaybackAfterOpeningBook()
        }
    }

    /// The file turned out to be unplayable once AVFoundation actually read it. Stop claiming
    /// it is playing: the statistics timer and the lock screen both key off the state.
    private func handlePlaybackFailed() {
        Log.audio.error("❌ GlobalAudioManager: Playback failed")
        playbackState = .failed
        playbackStateDidChange()
    }

    /// Drops everything pointing at the book — used when it is deleted from the library.
    func unload() {
        cancelDelayedStart()
        loadTask?.cancel()
        stopProgressPersistence()
        cancelSleepTimer()
        clearUndoSeek()
        teardownPlayer()
        currentAudiobook = nil
        pendingAutoplay = false
        pendingSeek = nil
        isLoading = false
        isReady = false
        playbackState = .stopped
        clearNowPlayingInfo()
        publishPlaybackSnapshot(reloadTimeline: true)
    }

    private func teardownPlayer() {
        guard let player else { return }
        player.tearDown()
        self.player = nil
    }

    // MARK: - Chapters

    /// Index of the chapter now playing, for the player screen and the chapter list.
    var currentChapterIndex: Int { player?.currentChapterIndex ?? 0 }

    func playChapter(at index: Int) {
        player?.playChapter(at: index)
        persistProgress()
        playbackStateDidChange()
    }
}
