import CryptoKit
import Foundation
import UIKit
import WatchConnectivity

// MARK: - The library snapshot, and the covers that go with it
extension WatchSyncService {
    /// How long a burst of "something changed" calls is allowed to coalesce. A playing book
    /// persists its position every five seconds, and every one of those would otherwise be a
    /// full application context.
    private static let debounce: Duration = .seconds(1)
    private static let sentCoversKey = "watchSentCovers"

    /// Queues a snapshot. Every mutation site calls this and nothing else; the debounce is what
    /// keeps progress ticks from spamming the link.
    func pushSnapshot(immediate: Bool = false) {
        snapshotTask?.cancel()
        guard !immediate else {
            sendSnapshot()
            return
        }
        snapshotTask = Task { @MainActor in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self.sendSnapshot()
        }
    }

    /// Builds and sends the snapshot, and hands back the bytes so a `sendMessage` reply can
    /// carry the very same state it just caused.
    @discardableResult
    func sendSnapshot() -> Data? {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else {
            return nil
        }
        let books = Self.selectBooks(from: AudiobookManager.shared.audiobooks, onWatch: booksOnWatch)
        let snapshot = LibrarySnapshot(
            books: books.map(Self.summary(for:)),
            nowPlaying: nowPlayingState(),
            skipBackSeconds: ThemeManager.shared.skipBackInterval.seconds,
            skipForwardSeconds: ThemeManager.shared.skipForwardInterval.seconds
        )
        guard let data = try? SyncCodec.encode(snapshot) else { return nil }
        do {
            try session.updateApplicationContext([SyncKeys.snapshot: data])
        } catch {
            // "Same context" and "not activated yet" both land here and both are harmless.
            Log.sync.debug("⌚️ WatchSyncService: context not updated — \(error.localizedDescription, privacy: .public)")
        }
        for book in books { sendCoverIfNeeded(for: book, over: session) }
        return data
    }

    /// The books whose covers and chapters the watch should see: whatever it already holds
    /// content for, then the most recently played unfinished books, three in all.
    static func selectBooks(
        from library: [AudiobookModel],
        onWatch: Set<UUID>,
        limit: Int = 3
    ) -> [AudiobookModel] {
        let recentFirst = { (lhs: AudiobookModel, rhs: AudiobookModel) in lhs.lastPlayed > rhs.lastPlayed }
        let held = library.filter { onWatch.contains($0.id) }.sorted(by: recentFirst)
        let rest = library
            .filter { !onWatch.contains($0.id) && !$0.isFinished }
            .sorted(by: recentFirst)
        return Array((held + rest).prefix(limit))
    }

    var booksOnWatch: Set<UUID> {
        Set(chaptersOnWatch.filter { !$0.value.isEmpty }.keys)
    }

    // MARK: - Pieces

    static func summary(for book: AudiobookModel) -> BookSummary {
        BookSummary(
            id: book.id,
            title: book.title ?? AudiobookModel.unknownTitle,
            author: book.author,
            duration: book.duration,
            currentPosition: book.currentPosition,
            positionUpdatedAt: book.positionUpdatedAt,
            playbackSpeed: book.playbackSpeed,
            isFinished: book.isFinished,
            chapters: book.sortedChapters.map {
                ChapterSummary(
                    number: Int($0.chapterNumber),
                    title: $0.title,
                    start: $0.startTime,
                    end: $0.endTime
                )
            },
            bookmarks: book.bookmarks.map {
                BookmarkSummary(id: $0.id, timestamp: $0.timestamp, title: $0.title, dateCreated: $0.dateCreated)
            }
        )
    }

    private func nowPlayingState() -> NowPlayingState? {
        let audio = GlobalAudioManager.shared
        guard let book = audio.currentAudiobook, audio.playbackState != .stopped else { return nil }
        return NowPlayingState(
            bookID: book.id,
            position: audio.getCurrentTime(),
            rate: audio.getPlaybackRate(),
            isPlaying: audio.playbackState == .playing
        )
    }

    // MARK: - Covers

    /// One 256 px JPEG per book, sent once. The digest is kept in defaults so a relaunch does
    /// not resend every cover, and so a replaced cover does get resent.
    private func sendCoverIfNeeded(for book: AudiobookModel, over session: WCSession) {
        guard let data = book.coverImageData else { return }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var sent = UserDefaults.standard.dictionary(forKey: Self.sentCoversKey) as? [String: String] ?? [:]
        guard sent[book.id.uuidString] != digest else { return }
        guard let jpeg = Self.thumbnail(from: data) else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-\(book.id.uuidString).jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            Log.sync.error("❌ WatchSyncService: could not stage a cover — \(error.localizedDescription, privacy: .public)")
            return
        }
        session.transferFile(url, metadata: TransferMetadata(kind: .cover, bookID: book.id).dictionary)
        sent[book.id.uuidString] = digest
        UserDefaults.standard.set(sent, forKey: Self.sentCoversKey)
    }

    private static func thumbnail(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}
