import Foundation
import SwiftUI
import MediaPlayer

@MainActor
@Observable
final class GlobalAudioManager: AudioManagerProtocol {
    static let shared = GlobalAudioManager()

    var currentAudiobook: AudiobookModel?
    /// The one player. Nil until a book is loaded.
    var player: AudiobookPlayer?
    var isLoading = false
    var isReady = false
    var showMiniPlayer = false
    var playbackState: PlaybackState = .stopped
    var sleepTimeRemaining: TimeInterval = 0

    var sleepTimer: Timer?
    /// Writes the playback position to the library while a book plays. See `+Progress`.
    var progressTimer: Timer?
    var pendingAutoplay = false
    var loadTask: Task<Void, Never>?

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
                showMiniPlayer = true
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
        loadTask?.cancel()
        teardownPlayer()

        currentAudiobook = audiobook
        showMiniPlayer = false
        isLoading = true
        isReady = false
        playbackState = .loading
        pendingAutoplay = false

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
        player = newPlayer

        if audiobook.currentPosition > 0 {
            newPlayer.seek(to: audiobook.currentPosition)
        }
        applyStoredSpeed(for: audiobook)

        isLoading = false
        isReady = true
        playbackState = .paused
        setupNowPlayingInfo(for: audiobook)
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
