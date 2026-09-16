import Foundation
import TipKit

/// The in-context tips: one per feature that is easy to miss, shown where the feature lives,
/// once the listener has used the app enough for it to matter. TipKit keeps the "seen" state.
enum AppTips {
    /// Donated each time the full player opens; the player tips count these.
    static let playerOpened = Tips.Event(id: "playerOpened")

    /// Set by the Settings "Reset Tips" row: TipKit wants its store reset before `configure`,
    /// so the reset waits for the next launch.
    static let resetPendingKey = "tips.resetPending"

    static func configure() {
        // UI tests and screenshots must not get a popover in the way of a tap.
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            Tips.hideAllTipsForTesting()
        }
        if UserDefaults.standard.bool(forKey: resetPendingKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.removeObject(forKey: resetPendingKey)
        }
        // At most one tip a day: a feature a day is learned, six in a row are dismissed.
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

// MARK: - Player

struct ChaptersTip: Tip {
    var title: Text { Text(NSLocalizedString("Chapters live here", comment: "Tip title: chapter counter")) }
    var message: Text? {
        Text(NSLocalizedString("Tap the counter to see every chapter and jump to one.", comment: "Tip message: chapter counter"))
    }
    var image: Image? { Image(systemName: "list.number") }
    var rules: [Rule] {
        #Rule(AppTips.playerOpened) { $0.donations.count >= 2 }
    }
}

struct SleepTimerTip: Tip {
    var title: Text { Text(NSLocalizedString("Sleep timer", comment: "Tip title: sleep timer")) }
    var message: Text? {
        Text(NSLocalizedString("Stop after a few minutes or at the end of the chapter. The volume fades out first.", comment: "Tip message: sleep timer"))
    }
    var image: Image? { Image(systemName: "moon.fill") }
    var rules: [Rule] {
        #Rule(AppTips.playerOpened) { $0.donations.count >= 4 }
    }
}

struct TranscriptTip: Tip {
    var title: Text { Text(NSLocalizedString("Read along", comment: "Tip title: transcript")) }
    var message: Text? {
        Text(NSLocalizedString("Transcribe the chapter on your device, follow the sentence being read and tap one to seek.", comment: "Tip message: transcript"))
    }
    var image: Image? { Image(systemName: "text.alignleft") }
    var rules: [Rule] {
        #Rule(AppTips.playerOpened) { $0.donations.count >= 6 }
    }
}

/// Shown once a "Next: …" row exists, which takes a queued or chained book.
struct QueueTip: Tip {
    @Parameter static var hasNext: Bool = false

    var title: Text { Text(NSLocalizedString("What plays next", comment: "Tip title: play queue")) }
    var message: Text? {
        Text(NSLocalizedString("Tap the \"Next\" row to see the queue, drag books into order or start one now.", comment: "Tip message: play queue"))
    }
    var image: Image? { Image(systemName: "text.line.first.and.arrowtriangle.forward") }
    var rules: [Rule] {
        #Rule(Self.$hasNext) { $0 }
    }
}

// MARK: - Library

struct LongPressBookTip: Tip {
    /// The library's book count, kept current by `LibraryView`.
    @Parameter static var bookCount: Int = 0

    var title: Text { Text(NSLocalizedString("Press and hold a book", comment: "Tip title: book context menu")) }
    var message: Text? {
        Text(NSLocalizedString("Queue it, add it to a collection, link it to Hardcover or send it to your watch.", comment: "Tip message: book context menu"))
    }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] {
        #Rule(Self.$bookCount) { $0 >= 3 }
    }
}

struct AutoContinueTip: Tip {
    var title: Text { Text(NSLocalizedString("Play the whole series", comment: "Tip title: collection auto-continue")) }
    var message: Text? {
        Text(NSLocalizedString("Turn on \"Play back to back\" and the next volume starts when this one ends.", comment: "Tip message: collection auto-continue"))
    }
    var image: Image? { Image(systemName: "books.vertical.fill") }
}

// MARK: - Settings

struct WatchTip: Tip {
    var title: Text { Text(NSLocalizedString("Listen on your watch", comment: "Tip title: Apple Watch")) }
    var message: Text? {
        Text(NSLocalizedString("Open a book and choose \"Send to Apple Watch\". Chapters arrive a few at a time and progress syncs both ways.", comment: "Tip message: Apple Watch"))
    }
    var image: Image? { Image(systemName: "applewatch") }
}
