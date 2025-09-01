import Foundation
import WidgetKit

enum NowPlayingSharedStore {
    // TODO: Set this to your actual App Group ID
    static var appGroupID: String = "group.io.jayet.AudiobookReader"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(audiobook: AudiobookModel?, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval, coverImageData: Data?) {
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
        if let cover = coverImageData {
            d.set(cover, forKey: "np_coverImageData")
        } else {
            d.removeObject(forKey: "np_coverImageData")
        }
        d.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
    }

    static func read() -> (title: String?, author: String?, isPlaying: Bool, current: TimeInterval, duration: TimeInterval, cover: Data?) {
        guard let d = defaults else { return (nil, nil, false, 0, 0, nil) }
        let title = d.string(forKey: "np_title")
        let author = d.string(forKey: "np_author")
        let isPlaying = d.bool(forKey: "np_isPlaying")
        let current = d.double(forKey: "np_currentTime")
        let duration = d.double(forKey: "np_duration")
        let cover = d.data(forKey: "np_coverImageData")
        return (title, author, isPlaying, current, duration, cover)
    }
}

