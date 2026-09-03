import os

/// App-wide loggers, one per area so Console and `log stream` can filter by category.
///
/// Prefer these over `print`: unified logging keeps release builds quiet, is cheap when nobody
/// is listening, and redacts interpolated values by default — book titles and file paths are
/// user data and must not land in a sysdiagnose. Mark a value `privacy: .public` only when it
/// carries no user data (a count, a duration, an enum case).
enum Log {
    private static let subsystem = "io.jayet.AudiobookReader"

    /// Playback engines, audio session, remote commands, now-playing.
    static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Picking, copying, unzipping and parsing incoming books.
    static let library = Logger(subsystem: subsystem, category: "library")
    /// SwiftData container lifecycle and backups.
    static let store = Logger(subsystem: subsystem, category: "store")
    /// Speech recognition and translation.
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    /// Views and view models.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
