import Foundation

/// One bounded stretch of one track: the unit a transcript is recognised, cached and shown in.
///
/// A single-file book used to be one "chapter", so opening the transcript meant recognising
/// the whole book before a word appeared. A request is at most `windowLength` long, so the text
/// around the playhead comes first and everything else is fetched as the listener reaches it.
struct TranscriptionRequest: Hashable, Sendable {
    static let windowLength: TimeInterval = 10 * 60

    let audiobookID: UUID
    let url: URL
    let trackIndex: Int
    /// Track-local seconds, the same timeline the recogniser and the cached segments use.
    let start: TimeInterval
    let end: TimeInterval
    /// Where the track starts in the book: added to segment times for display and seeking.
    let trackStart: TimeInterval
    /// The embedded chapter's title when the window is one, else nil.
    let title: String?
    /// The reader's chosen recognition language for this book, as a locale identifier. Nil
    /// means the language the file declares, else the device's.
    var language: String?

    var bookRange: Range<TimeInterval> { (trackStart + start)..<(trackStart + end) }

    func contains(bookTime: TimeInterval) -> Bool { bookRange.contains(bookTime) }

    /// The window around `time`: the whole track when it fits in one, the embedded chapter of a
    /// single-file book when that fits, else a fixed window aligned to the start of the track
    /// so the same position always yields the same cache key. Nil until the player has tracks.
    static func make(
        audiobookID: UUID,
        chapters: [ChapterModel],
        tracks: [AudiobookTrack],
        time: TimeInterval,
        language: String? = nil
    ) -> TranscriptionRequest? {
        guard !tracks.isEmpty else { return nil }
        let index = AudiobookPlayer.trackIndex(at: time, in: tracks)
        let track = tracks[index]
        guard track.duration > 0 else { return nil }

        var start: TimeInterval = 0
        var end = track.duration
        var title: String?

        if track.duration > windowLength {
            // Embedded chapter markers are only trusted on single-file books: a folder book's
            // chapter rows describe its files, which are the tracks already.
            if tracks.count == 1,
               let chapter = chapters.first(where: { $0.startTime <= time && time < $0.endTime }),
               chapter.endTime - chapter.startTime <= windowLength {
                start = chapter.startTime
                end = min(chapter.endTime, track.duration)
                title = chapter.title
            } else {
                let local = min(max(time - track.start, 0), track.duration.nextDown)
                start = floor(local / windowLength) * windowLength
                end = min(start + windowLength, track.duration)
            }
        }

        return TranscriptionRequest(
            audiobookID: audiobookID,
            url: track.url,
            trackIndex: index,
            start: start,
            end: end,
            trackStart: track.start,
            title: title,
            language: language
        )
    }

    // MARK: - Per-book language

    /// The chosen language for a book. UserDefaults, not a column: adding a column to a shared
    /// model class would change earlier schema versions' checksums.
    static func storedLanguage(for audiobookID: UUID) -> String? {
        UserDefaults.standard.string(forKey: "transcription.language.\(audiobookID.uuidString)")
    }

    /// Whether the language question was put to the user for this book. Its own flag, so
    /// keeping the default leaves the stored language nil and the cache keys unchanged.
    static func languageAsked(for audiobookID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: "transcription.languageAsked.\(audiobookID.uuidString)")
    }

    static func markLanguageAsked(for audiobookID: UUID) {
        UserDefaults.standard.set(true, forKey: "transcription.languageAsked.\(audiobookID.uuidString)")
    }

    static func storeLanguage(_ language: String?, for audiobookID: UUID) {
        let key = "transcription.language.\(audiobookID.uuidString)"
        if let language {
            UserDefaults.standard.set(language, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
