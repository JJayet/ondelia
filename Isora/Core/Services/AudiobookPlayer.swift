import Foundation
import AVFoundation

/// One audio file placed on the book's timeline.
///
/// A single-file book has exactly one of these, so the rest of the player never needs to know
/// which kind of book it is holding.
struct AudiobookTrack: Sendable, Equatable {
    let url: URL
    /// Offset of this file from the start of the book.
    let start: TimeInterval
    let duration: TimeInterval

    var end: TimeInterval { start + duration }
}

/// Plays an audiobook, whether it is one file or a folder of chapter files.
///
/// Built on `AVQueuePlayer`, which already does what the two previous engines did by hand: it
/// preloads the next item, advances at the end of one, and keeps only a small window buffered.
/// All this type adds is the timeline — mapping between a position in the book and a position
/// inside whichever file is playing.
///
/// Everything runs on the main actor. The old engines drove `AVPlayer` from private dispatch
/// queues and wrote player state from several of them at once, which is what made their state
/// races possible. The audio session and the remote controls are process-wide rather than
/// per-book, so they live on `GlobalAudioManager` instead of here.
@MainActor
@Observable
final class AudiobookPlayer {
    /// Exposed so the manager and tests can inspect the underlying player.
    let player = AVQueuePlayer()

    private(set) var isPlaying = false
    /// Position in the book, not in the current file.
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackRate: Float = 1
    private(set) var currentChapterIndex = 0
    private(set) var tracks: [AudiobookTrack] = []

    /// Called when the queue runs out, so the manager can settle its own state.
    var onPlaybackEnded: (@MainActor () -> Void)?
    /// Called when AVFoundation rejects the item that was supposed to play. A file can pass
    /// loading — the manifest carries its duration — and only fail once it is decoded.
    var onPlaybackFailed: (@MainActor () -> Void)?

    /// Maps a queued item back to its track, so a tick can tell where playback has reached.
    private var trackIndexByItem: [ObjectIdentifier: Int] = [:]
    private var timeObserver: Any?

    init() {
        player.actionAtItemEnd = .advance
        player.allowsExternalPlayback = false
    }

    /// Stops playback and releases the queue. The manager calls this before dropping the player
    /// rather than relying on `deinit` running at a useful moment — which is what the old
    /// engines did, leaving remote-control targets registered against dead objects.
    func tearDown() {
        pause()
        removeTimeObserver()
        player.removeAllItems()
        trackIndexByItem.removeAll()
        tracks = []
        currentTime = 0
        duration = 0
        currentChapterIndex = 0
    }

    // MARK: - Loading

    /// Reads the book's layout off the main actor, then queues it.
    /// Returns false when the book has no playable audio.
    @discardableResult
    func load(_ audiobook: AudiobookModel) async -> Bool {
        guard let url = audiobook.resolvedFileURL else {
            Log.audio.error("❌ AudiobookPlayer: No resolved file URL")
            return false
        }
        let newTracks = await Self.makeTracks(at: url, fallbackDuration: audiobook.duration)
        guard !newTracks.isEmpty else {
            Log.audio.error("❌ AudiobookPlayer: No playable audio at \(url.lastPathComponent)")
            return false
        }

        tracks = newTracks
        // A stored total can disagree with the files on disk; the timeline we actually play wins.
        duration = newTracks.last?.end ?? 0
        currentTime = 0
        moveQueue(to: 0)
        addTimeObserver()
        Log.audio.debug("✅ AudiobookPlayer: Loaded \(newTracks.count) track(s)")
        return true
    }

    /// Rebuilds the queue so `index` plays next. `AVQueuePlayer` only ever moves forwards, so
    /// reaching an earlier chapter means handing it a fresh queue.
    ///
    /// ponytail: queues every remaining track at once. AVQueuePlayer buffers only the head, so
    /// this stays cheap for a few hundred chapters; window it if profiling ever says otherwise.
    private func moveQueue(to index: Int) {
        player.removeAllItems()
        trackIndexByItem.removeAll()
        guard tracks.indices.contains(index) else { return }
        for offset in index..<tracks.count {
            let item = AVPlayerItem(url: tracks[offset].url)
            trackIndexByItem[ObjectIdentifier(item)] = offset
            player.insert(item, after: nil)
        }
        currentChapterIndex = index
    }

    // MARK: - Transport

    func play() {
        guard !tracks.isEmpty else { return }
        // `defaultRate` makes `play()` resume at the listener's speed. The old engines set
        // `rate` directly, which both starts playback and sets the speed, so a rate chosen
        // while paused was silently dropped on resume.
        player.defaultRate = playbackRate
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    /// Seeks to a position in the book, crossing into another file when needed.
    func seek(to time: TimeInterval) {
        guard !tracks.isEmpty else { return }
        // NaN has to be rejected before the clamp, not after: `max(NaN, 0)` is NaN, because
        // every comparison against NaN is false, so it would sail through into an invalid
        // CMTime and AVPlayer would raise on the seek.
        guard time.isFinite else {
            Log.audio.warning("⚠️ AudiobookPlayer: Ignoring a seek to a non-finite time")
            return
        }
        let target = min(max(time, 0), duration)
        let index = trackIndex(at: target)

        if index != currentChapterIndex || player.currentItem == nil {
            moveQueue(to: index)
        }

        let withinTrack = max(target - tracks[index].start, 0)
        let cmTime = CMTime(seconds: withinTrack, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Exact seeks: someone re-reading a sentence cares more about landing on the right
        // words than about the seek being instant.
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target

        if isPlaying {
            player.defaultRate = playbackRate
            player.play()
        }
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBackward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    /// Used by the sleep timer's fade-out. Reset to 1 whenever the timer is cancelled.
    func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    func setPlaybackRate(_ rate: Float) {
        guard rate.isFinite, rate > 0 else { return }
        playbackRate = rate
        player.defaultRate = rate
        // Assigning `rate` on a paused player would start it, so only a playing one is retimed.
        if isPlaying {
            player.rate = rate
        }
    }

    /// Jumps to the start of a chapter.
    func playChapter(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        seek(to: tracks[index].start)
    }

    // MARK: - Timeline

    /// Index of the track covering `time`, clamped to the book.
    func trackIndex(at time: TimeInterval) -> Int {
        Self.trackIndex(at: time, in: tracks)
    }

    /// Pure so it can be exercised without a player or an audio file.
    nonisolated static func trackIndex(at time: TimeInterval, in tracks: [AudiobookTrack]) -> Int {
        guard !tracks.isEmpty else { return 0 }
        if let index = tracks.firstIndex(where: { time >= $0.start && time < $0.end }) {
            return index
        }
        // A missing chapter file leaves a hole in the timeline it used to fill. Landing in one
        // continues from the next file there is, rather than jumping to the end of the book.
        if let next = tracks.firstIndex(where: { $0.start > time }) {
            return next
        }
        return tracks.count - 1
    }

    // MARK: - Progress

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Delivered on the main queue, which is already where this class lives.
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func removeTimeObserver() {
        guard let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func tick() {
        guard !tracks.isEmpty else { return }
        guard let item = player.currentItem,
              let index = trackIndexByItem[ObjectIdentifier(item)] else {
            // Queue drained: the book played through to its end.
            guard isPlaying else { return }
            isPlaying = false
            currentTime = duration
            onPlaybackEnded?()
            return
        }
        // A file that cannot be decoded fails here rather than at load, so this is where
        // "playing" has to stop being claimed for something that is silent.
        if item.status == .failed {
            Log.audio.error("❌ AudiobookPlayer: Item failed: \(item.error?.localizedDescription ?? "unknown")")
            pause()
            onPlaybackFailed?()
            return
        }

        // The queue advances on its own, so noticing the new chapter here is all it takes —
        // no transition step, no flag, no observer to move.
        currentChapterIndex = index
        let withinTrack = item.currentTime().seconds
        guard withinTrack.isFinite else { return }
        currentTime = min(tracks[index].start + max(withinTrack, 0), duration)
    }
}
