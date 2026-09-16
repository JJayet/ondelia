import Foundation

/// Extra chapter-progress keys the watch app writes into the shared app-group suite
/// (`group.io.jayet.isora`), alongside the `np_*` keys already read by
/// `NowPlayingSharedStore.read()`:
///   - `np_chapterTitle`  (String) — current chapter's title
///   - `np_chapterStart`  (Double) — chapter start offset within the book, in seconds
///   - `np_chapterEnd`    (Double) — chapter end offset within the book, in seconds
///   - `np_chapterNumber` (Int)    — 1-based chapter number
/// When any of the three numeric keys is missing, the widget falls back to whole-book progress.
struct WatchNowPlayingSnapshot {
    let title: String?
    let author: String?
    let isPlaying: Bool
    let current: TimeInterval
    let duration: TimeInterval
    let cover: Data?
    let rate: Float
    let chapterTitle: String?
    let chapterNumber: Int?
    let chapterStart: TimeInterval?
    let chapterEnd: TimeInterval?

    static func read() -> WatchNowPlayingSnapshot {
        let base = NowPlayingSharedStore.read()
        let defaults = UserDefaults(suiteName: NowPlayingSharedStore.appGroupID)
        return WatchNowPlayingSnapshot(
            title: base.title,
            author: base.author,
            isPlaying: base.isPlaying,
            current: base.current,
            duration: base.duration,
            cover: base.cover,
            rate: base.playbackRate,
            chapterTitle: defaults?.string(forKey: "np_chapterTitle"),
            chapterNumber: defaults?.object(forKey: "np_chapterNumber") != nil
                ? defaults?.integer(forKey: "np_chapterNumber") : nil,
            chapterStart: defaults?.object(forKey: "np_chapterStart") != nil
                ? defaults?.double(forKey: "np_chapterStart") : nil,
            chapterEnd: defaults?.object(forKey: "np_chapterEnd") != nil
                ? defaults?.double(forKey: "np_chapterEnd") : nil
        )
    }

    /// A copy projected `elapsed` seconds forward — used to build the "end of chapter" timeline
    /// entry without a second `UserDefaults` read.
    func advanced(by elapsed: TimeInterval) -> WatchNowPlayingSnapshot {
        guard isPlaying, elapsed > 0 else { return self }
        return WatchNowPlayingSnapshot(
            title: title,
            author: author,
            isPlaying: isPlaying,
            current: min(current + elapsed, max(duration, current)),
            duration: duration,
            cover: cover,
            rate: rate,
            chapterTitle: chapterTitle,
            chapterNumber: chapterNumber,
            chapterStart: chapterStart,
            chapterEnd: chapterEnd
        )
    }

    /// Percent of the current chapter, falling back to percent of the whole book when the
    /// chapter bounds are missing.
    var progressPercent: Int {
        if let start = chapterStart, let end = chapterEnd, end > start {
            let fraction = (current - start) / (end - start)
            return Int((min(max(fraction, 0), 1) * 100).rounded())
        }
        guard duration > 0 else { return 0 }
        return Int((min(max(current / duration, 0), 1) * 100).rounded())
    }

    /// Time left in the book (not the chapter) — used on the rectangular family.
    var remainingInBook: TimeInterval {
        max(duration - current, 0)
    }
}
