import AppIntents
import SwiftData

// Spotlight / Siri App Shortcuts. Run in the app process; the system launches the app in the
// background when needed, so these talk to GlobalAudioManager directly.

/// Siri reads these out; a success needs no line of its own — the audio starting is the answer.
enum PlaybackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyLibrary
    case nothingPlaying
    case bookMissing

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyLibrary: return "No audiobook in your library"
        case .nothingPlaying: return "Nothing is playing"
        case .bookMissing: return "That audiobook is no longer in your library"
        }
    }
}

struct ResumeLastBookIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Resume Last Book"
    static let description = IntentDescription("Resume the most recently played audiobook")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await PlaybackCommands.loadedBook() != nil else { throw PlaybackIntentError.emptyLibrary }
        GlobalAudioManager.shared.startPlayback() // queued via pendingAutoplay until ready
        return .result()
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
    func perform() async throws -> some IntentResult {
        let manager = GlobalAudioManager.shared
        guard manager.currentAudiobook != nil else { throw PlaybackIntentError.nothingPlaying }
        manager.setSleepTimerEndOfChapter()
        return .result()
    }
}

/// One audiobook, as Siri and Shortcuts see it.
struct AudiobookEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Audiobook")
    static let defaultQuery = AudiobookEntityQuery()

    let id: UUID
    let title: String
    let author: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: author)
        )
    }
}

struct AudiobookEntityQuery: EntityStringQuery {
    @MainActor
    private func books(matching predicate: Predicate<AudiobookModel>?) async -> [AudiobookEntity] {
        let store = SwiftDataController.shared
        await store.whenLoaded()
        guard store.isLoaded else { return [] }
        let descriptor = FetchDescriptor<AudiobookModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastPlayed, order: .reverse)]
        )
        let models = (try? store.context.fetch(descriptor)) ?? []
        return models.map {
            AudiobookEntity(
                id: $0.id,
                title: $0.title ?? AudiobookModel.unknownTitle,
                author: $0.author ?? AudiobookModel.unknownAuthor
            )
        }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AudiobookEntity] {
        await books(matching: #Predicate { identifiers.contains($0.id) })
    }

    @MainActor
    func entities(matching string: String) async throws -> [AudiobookEntity] {
        // Matched in Swift: `localizedStandardContains` is not something the store can compile
        // into a predicate, and a library is small enough to filter in memory.
        await books(matching: nil).filter {
            $0.title.localizedStandardContains(string) || $0.author.localizedStandardContains(string)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [AudiobookEntity] {
        Array(await books(matching: nil).prefix(10))
    }
}

struct PlayAudiobookIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Audiobook"
    static let description = IntentDescription("Play a specific audiobook from your library")

    @Parameter(title: "Audiobook")
    var audiobook: AudiobookEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = SwiftDataController.shared
        await store.whenLoaded()
        let id = audiobook.id
        var descriptor = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let book = try? store.context.fetch(descriptor).first else { throw PlaybackIntentError.bookMissing }
        let manager = GlobalAudioManager.shared
        manager.loadAudiobook(book)
        manager.startPlayback() // queued via pendingAutoplay until the engine is ready
        return .result()
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
            intent: PlayAudiobookIntent(),
            phrases: [
                "Play \(\.$audiobook) in \(.applicationName)",
                "Listen to \(\.$audiobook) in \(.applicationName)"
            ],
            shortTitle: "Play Audiobook",
            systemImageName: "book.fill"
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
