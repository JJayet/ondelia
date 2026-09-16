import Foundation

/// The persisted list of chapters waiting to be exported and shipped to the watch.
///
/// Queue bookkeeping only: no `WCSession`, no exporter. A chapter export can easily outlive
/// the background window a watch message buys, so the list has to survive a relaunch and be
/// picked up again — which is the whole reason it is a stored thing and not a local array in
/// the sync service.
@MainActor
@Observable
final class WatchTransferQueue {
    static let shared = WatchTransferQueue()

    struct PendingChapter: Codable, Sendable, Equatable, Identifiable {
        enum State: Codable, Sendable, Equatable {
            case queued
            case exporting
            case sending(fraction: Double)
            case sent
            case failed(String)
        }

        let bookID: UUID
        let chapterNumber: Int
        var state: State

        var id: String { "\(bookID.uuidString)#\(chapterNumber)" }

        init(bookID: UUID, chapterNumber: Int, state: State = .queued) {
            self.bookID = bookID
            self.chapterNumber = chapterNumber
            self.state = state
        }
    }

    private(set) var pending: [PendingChapter] = []

    private let defaults: UserDefaults
    private let storageKey = "watchTransferQueue"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? SyncCodec.decode([PendingChapter].self, from: data) else {
            return
        }
        pending = stored
    }

    /// The chapters that should be on the watch when the listener is at `currentChapter`:
    /// that one and the next `width - 1`, so a transfer has time to land before it is needed.
    /// Chapter numbers are 1-based, as the importers write them.
    static func desiredWindow(currentChapter: Int, chapterCount: Int, width: Int = 3) -> [Int] {
        guard chapterCount > 0, width > 0 else { return [] }
        let start = min(max(currentChapter, 1), chapterCount)
        let end = min(start + width - 1, chapterCount)
        return Array(start...end)
    }

    /// The chapters worth sending for a listener at `currentChapter`: the window, minus whatever
    /// the watch already holds. The current chapter is always kept — a request for it means the
    /// watch does not have it, whatever a stale inventory says.
    static func chaptersToSend(
        currentChapter: Int,
        chapterCount: Int,
        alreadyOnWatch: Set<Int>,
        width: Int = 3
    ) -> [Int] {
        desiredWindow(currentChapter: currentChapter, chapterCount: chapterCount, width: width)
            .filter { $0 == currentChapter || !alreadyOnWatch.contains($0) }
    }

    /// Appends the chapters that are not already tracked, keeping request order. A chapter that
    /// failed before is put back in line rather than skipped, or one bad export would retire it
    /// for good — the "Send to Apple Watch" button included.
    func enqueue(bookID: UUID, chapters: [Int]) {
        var changed = false
        for number in chapters {
            let index = pending.firstIndex { $0.bookID == bookID && $0.chapterNumber == number }
            guard let index else {
                pending.append(PendingChapter(bookID: bookID, chapterNumber: number))
                changed = true
                continue
            }
            guard case .failed = pending[index].state else { continue }
            pending[index].state = .queued
            changed = true
        }
        guard changed else { return }
        save()
    }

    /// The next chapter to work on: the oldest one nobody has started.
    func next() -> PendingChapter? {
        pending.first { $0.state == .queued }
    }

    func update(_ item: PendingChapter, state: PendingChapter.State) {
        guard let index = pending.firstIndex(where: { $0.id == item.id }) else { return }
        guard pending[index].state != state else { return }
        pending[index].state = state
        save()
    }

    func remove(bookID: UUID, chapterNumber: Int) {
        let remaining = pending.filter { !($0.bookID == bookID && $0.chapterNumber == chapterNumber) }
        guard remaining.count != pending.count else { return }
        pending = remaining
        save()
    }

    func clear(bookID: UUID) {
        let remaining = pending.filter { $0.bookID != bookID }
        guard remaining.count != pending.count else { return }
        pending = remaining
        save()
    }

    private func save() {
        guard let data = try? SyncCodec.encode(pending) else {
            Log.sync.error("❌ WatchTransferQueue: could not encode the queue")
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
