import Foundation
import UIKit
import WatchConnectivity

// MARK: - Exporting chapters and shipping them to the watch
extension WatchSyncService {
    /// Only the sender sees a transfer's progress, so it is forwarded — but not on every KVO
    /// tick, which fires far more often than a watch screen can use.
    private static let progressForwardInterval: TimeInterval = 2

    /// "Send to Apple Watch": the chapter the listener is in and the two after it.
    func sendToWatch(book: AudiobookModel) {
        let chapters = book.sortedChapters
        guard !chapters.isEmpty else { return }
        let current = chapters.last { $0.startTime <= book.currentPosition } ?? chapters[0]
        enqueueWindow(bookID: book.id, around: Int(current.chapterNumber), chapterCount: chapters.count)
    }

    /// The rolling window around one chapter, skipping what the watch says it already holds so a
    /// request does not re-export and re-ship chapters that are sitting there.
    func enqueueWindow(bookID: UUID, around chapter: Int, chapterCount: Int) {
        let wanted = WatchTransferQueue.chaptersToSend(
            currentChapter: chapter,
            chapterCount: chapterCount,
            alreadyOnWatch: chaptersOnWatch[bookID] ?? []
        )
        guard !wanted.isEmpty else { return }
        WatchTransferQueue.shared.enqueue(bookID: bookID, chapters: wanted)
        drainQueue()
    }

    /// Exports and ships queued chapters one at a time. Re-entrant callers are ignored; the
    /// loop picks up anything enqueued while it was running, and `didFinish` calls back in.
    func drainQueue() {
        guard !isDraining else { return }
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        isDraining = true
        Task { @MainActor in
            while let item = WatchTransferQueue.shared.next() {
                await ship(item)
            }
            self.isDraining = false
        }
    }

    private func ship(_ item: WatchTransferQueue.PendingChapter) async {
        let queue = WatchTransferQueue.shared
        guard let book = book(item.bookID),
              let chapter = book.sortedChapters.first(where: { Int($0.chapterNumber) == item.chapterNumber })
        else {
            queue.remove(bookID: item.bookID, chapterNumber: item.chapterNumber)
            return
        }
        queue.update(item, state: .exporting)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(item.bookID.uuidString)-\(item.chapterNumber).m4a")
        // A watch request wakes the app in the background; a long chapter easily outlives the
        // window, so buy what time there is and let the persisted queue resume the rest.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "WatchChapterExport")
        do {
            let source = try WatchAudioExporter.exportSource(for: book, chapter: chapter)
            try await WatchAudioExporter.export(source, to: url)
        } catch {
            Log.sync.error("❌ WatchSyncService: export failed — \(error.localizedDescription, privacy: .public)")
            queue.update(item, state: .failed(error.localizedDescription))
            try? FileManager.default.removeItem(at: url)
            endBackgroundTask(backgroundTask)
            return
        }
        endBackgroundTask(backgroundTask)
        startTransfer(of: url, for: item, duration: chapter.endTime - chapter.startTime)
    }

    private func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }

    private func startTransfer(
        of url: URL,
        for item: WatchTransferQueue.PendingChapter,
        duration: TimeInterval
    ) {
        let queue = WatchTransferQueue.shared
        guard let session, session.activationState == .activated else {
            queue.update(item, state: .failed("no session"))
            try? FileManager.default.removeItem(at: url)
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        let metadata = TransferMetadata(
            kind: .chapter,
            bookID: item.bookID,
            chapterNumber: item.chapterNumber,
            duration: duration,
            byteCount: size
        )
        let transfer = session.transferFile(url, metadata: metadata.dictionary)
        queue.update(item, state: .sending(fraction: 0))
        transferObservations[item.id] = transfer.progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                WatchSyncService.shared.transferDidProgress(item, fraction: fraction)
            }
        }
    }

    func transferDidProgress(_ item: WatchTransferQueue.PendingChapter, fraction: Double) {
        WatchTransferQueue.shared.update(item, state: .sending(fraction: fraction))
        guard isReachable,
              Date().timeIntervalSince(lastTransferProgressAt) >= Self.progressForwardInterval else { return }
        lastTransferProgressAt = Date()
        send(.transferProgress(
            bookID: item.bookID,
            chapterNumber: item.chapterNumber,
            fraction: fraction
        ), urgent: true)
    }

    /// The transfer finished, one way or the other. The staged file is ours to delete either way.
    func finishTransfer(at url: URL, metadata: TransferMetadata?, error: String?) {
        try? FileManager.default.removeItem(at: url)
        guard let metadata, metadata.kind == .chapter, let number = metadata.chapterNumber else { return }
        let item = WatchTransferQueue.PendingChapter(bookID: metadata.bookID, chapterNumber: number)
        transferObservations[item.id] = nil
        if let error {
            Log.sync.error("❌ WatchSyncService: transfer failed — \(error, privacy: .public)")
            WatchTransferQueue.shared.update(item, state: .failed(error))
        } else {
            WatchTransferQueue.shared.update(item, state: .sent)
            markOnWatch(bookID: metadata.bookID, chapterNumber: number, present: true)
        }
        drainQueue()
    }

    // MARK: - What the UI shows

    /// The chapter of `bookID` currently on its way, if any.
    func inFlight(for bookID: UUID) -> WatchTransferQueue.PendingChapter? {
        WatchTransferQueue.shared.pending.first {
            guard $0.bookID == bookID else { return false }
            switch $0.state {
            case .exporting, .sending, .queued: return true
            case .sent, .failed: return false
            }
        }
    }
}
