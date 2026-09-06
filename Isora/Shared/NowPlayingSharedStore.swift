import Foundation
import WidgetKit
import CoreFoundation

enum PlaybackCommand: String, Codable, Sendable {
    case toggle
    case skipForward
    case skipBackward
}

/// Nonisolated on purpose: the widget extension and the App Intents both read and write this
/// from outside the main actor. It owns no state of its own — everything lives in the shared
/// UserDefaults suite and one file in the app group container.
nonisolated enum NowPlayingSharedStore {
    static let appGroupID = "group.io.jayet.isora"
    static let commandNotificationName = "group.io.jayet.isora.playback-command"
    private static let coverFileName = "now-playing-cover.jpg"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(
        audiobook: AudiobookModel?,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        coverImageData: Data?,
        playbackRate: Float = 1,
        reloadTimeline: Bool = true,
        chapter: (title: String?, number: Int, start: TimeInterval, end: TimeInterval)? = nil
    ) {
        guard let d = defaults else { return }
        if let book = audiobook {
            d.set(book.title ?? "", forKey: "np_title")
            d.set(book.author ?? "", forKey: "np_author")
        } else {
            d.removeObject(forKey: "np_title")
            d.removeObject(forKey: "np_author")
        }
        d.set(isPlaying, forKey: "np_isPlaying")
        d.set(currentTime, forKey: "np_currentTime")
        d.set(duration, forKey: "np_duration")
        d.set(Date().timeIntervalSince1970, forKey: "np_updatedAt")
        d.set(playbackRate, forKey: "np_playbackRate")
        persistCover(coverImageData)
        d.removeObject(forKey: "np_coverImageData") // Remove data written by older versions.
        writeChapter(chapter, into: d)
        if reloadTimeline {
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }

    /// The watch complication draws chapter progress, so the watch app writes four extra keys
    /// alongside the book-level ones. Nil clears them, which is what makes the widget fall
    /// back to whole-book progress.
    private static func writeChapter(
        _ chapter: (title: String?, number: Int, start: TimeInterval, end: TimeInterval)?,
        into d: UserDefaults
    ) {
        guard let chapter else {
            for key in ["np_chapterTitle", "np_chapterStart", "np_chapterEnd", "np_chapterNumber"] {
                d.removeObject(forKey: key)
            }
            return
        }
        if let title = chapter.title, !title.isEmpty {
            d.set(title, forKey: "np_chapterTitle")
        } else {
            d.removeObject(forKey: "np_chapterTitle")
        }
        d.set(chapter.start, forKey: "np_chapterStart")
        d.set(chapter.end, forKey: "np_chapterEnd")
        d.set(chapter.number, forKey: "np_chapterNumber")
    }

    /// Each platform has exactly one now-playing widget, and they do not share a kind.
    private static var widgetKind: String {
        #if os(watchOS)
        "IsoraWatchNowPlaying"
        #else
        "NowPlayingWidget"
        #endif
    }

    static func read() -> (
        title: String?,
        author: String?,
        isPlaying: Bool,
        current: TimeInterval,
        duration: TimeInterval,
        cover: Data?,
        updatedAt: Date,
        playbackRate: Float
    ) {
        guard let d = defaults else { return (nil, nil, false, 0, 0, nil, Date(), 1) }
        let title = d.string(forKey: "np_title")
        let author = d.string(forKey: "np_author")
        let isPlaying = d.bool(forKey: "np_isPlaying")
        let snapshotTime = d.double(forKey: "np_currentTime")
        let duration = d.double(forKey: "np_duration")
        let updatedAt = Date(timeIntervalSince1970: d.double(forKey: "np_updatedAt"))
        let storedRate = d.float(forKey: "np_playbackRate")
        let playbackRate = storedRate > 0 ? storedRate : 1
        let elapsed = isPlaying ? max(Date().timeIntervalSince(updatedAt), 0) * Double(playbackRate) : 0
        let current = min(max(snapshotTime + elapsed, 0), max(duration, 0))
        return (title, author, isPlaying, current, duration, coverImageData(), updatedAt, playbackRate)
    }

    static func send(_ command: PlaybackCommand) {
        guard let defaults else { return }
        defaults.set(command.rawValue, forKey: "playback_command")
        defaults.set(Date().timeIntervalSince1970, forKey: "playback_command_created_at")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(commandNotificationName as CFString),
            nil,
            nil,
            true
        )
    }

    static func consumePlaybackCommand(now: Date = Date()) -> PlaybackCommand? {
        guard let defaults,
              let rawValue = defaults.string(forKey: "playback_command") else { return nil }
        let createdAt = Date(timeIntervalSince1970: defaults.double(forKey: "playback_command_created_at"))
        defaults.removeObject(forKey: "playback_command")
        defaults.removeObject(forKey: "playback_command_created_at")
        guard now.timeIntervalSince(createdAt) >= 0,
              now.timeIntervalSince(createdAt) <= 30 else { return nil }
        return PlaybackCommand(rawValue: rawValue)
    }

    static func coverImageData() -> Data? {
        guard let url = coverFileURL else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static var coverFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(coverFileName)
    }

    private static func persistCover(_ data: Data?) {
        guard let url = coverFileURL else { return }
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if let existing = try? Data(contentsOf: url, options: [.mappedIfSafe]), existing == data {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
