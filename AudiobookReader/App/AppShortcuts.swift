import AppIntents
import SwiftData

// Spotlight / Siri App Shortcuts. Run in the app process; the system launches the app in the
// background when needed, so these talk to GlobalAudioManager directly.

struct ResumeLastBookIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Resume Last Book"
    static let description = IntentDescription("Resume the most recently played audiobook")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SwiftDataController.shared
        while !store.isLoaded && store.loadErrorMessage == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard store.isLoaded else { return .result(dialog: "Library Unavailable") }

        let manager = GlobalAudioManager.shared
        if let current = manager.currentAudiobook {
            manager.startPlayback()
            return .result(dialog: "Resuming \(current.title ?? "")")
        }
        var descriptor = FetchDescriptor<AudiobookModel>(
            sortBy: [SortDescriptor(\.lastPlayed, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let book = try store.context.fetch(descriptor).first else {
            return .result(dialog: "No audiobook in your library")
        }
        manager.loadAudiobook(book)
        manager.startPlayback() // queued via pendingAutoplay until the engine is ready
        return .result(dialog: "Resuming \(book.title ?? "")")
    }
}

struct PausePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause Playback"
    static let description = IntentDescription("Pause the current audiobook")

    @MainActor
    func perform() async throws -> some IntentResult {
        GlobalAudioManager.shared.pausePlayback()
        return .result()
    }
}

struct SleepEndOfChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Sleep at End of Chapter"
    static let description = IntentDescription("Stop playback when the current chapter ends")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = GlobalAudioManager.shared
        guard manager.currentAudiobook != nil else { return .result(dialog: "Nothing is playing") }
        manager.setSleepTimerEndOfChapter()
        return .result(dialog: "Sleep timer set")
    }
}

struct AudiobookShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeLastBookIntent(),
            phrases: [
                "Resume my book in \(.applicationName)",
                "Resume last book in \(.applicationName)",
                "Continue listening in \(.applicationName)"
            ],
            shortTitle: "Resume Last Book",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause my book in \(.applicationName)"
            ],
            shortTitle: "Pause Playback",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: SleepEndOfChapterIntent(),
            phrases: [
                "Sleep at end of chapter in \(.applicationName)",
                "Stop at end of chapter in \(.applicationName)"
            ],
            shortTitle: "Sleep at End of Chapter",
            systemImageName: "moon.fill"
        )
    }
}
