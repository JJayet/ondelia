import Foundation
import SwiftData

/// Transport commands that may arrive before anything is loaded — from a widget, Control Center
/// or Siri, with the app cold-launched into the background to serve them.
///
/// The audio engine only exists in the app process, so every one of these paths has to be able
/// to wait for the store and pick the book back up on its own.
@MainActor
enum PlaybackCommands {
    /// The book the transport should act on: whatever is loaded, else the most recently played.
    /// Returns nil when the store failed to open or the library is empty.
    @discardableResult
    static func loadedBook() async -> AudiobookModel? {
        let store = SwiftDataController.shared
        await store.whenLoaded()
        guard store.isLoaded else { return nil }

        let audio = GlobalAudioManager.shared
        if let current = audio.currentAudiobook { return current }

        var descriptor = FetchDescriptor<AudiobookModel>(
            sortBy: [SortDescriptor(\.lastPlayed, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let book = try? store.context.fetch(descriptor).first else { return nil }
        audio.loadAudiobook(book)
        return book
    }

    /// The book a media intent names: by donated identifier, else by title, else the one that
    /// would resume anyway. Waits for the store, since Siri can cold-launch the app.
    static func book(identifier: String?, named name: String?) async -> AudiobookModel? {
        let store = SwiftDataController.shared
        await store.whenLoaded()
        guard store.isLoaded else { return nil }

        if let identifier, let id = UUID(uuidString: identifier) {
            let descriptor = FetchDescriptor<AudiobookModel>(
                predicate: #Predicate<AudiobookModel> { $0.id == id }
            )
            if let match = try? store.context.fetch(descriptor).first { return match }
        }
        if let name, !name.isEmpty {
            let descriptor = FetchDescriptor<AudiobookModel>(
                predicate: #Predicate<AudiobookModel> { $0.title == name }
            )
            if let match = try? store.context.fetch(descriptor).first { return match }
        }
        return await loadedBook()
    }

    /// Loads a book and starts it. `loadAudiobook` is asynchronous, so the play is queued
    /// through the autoplay the manager already keeps for this case.
    static func play(_ audiobook: AudiobookModel) {
        let audio = GlobalAudioManager.shared
        audio.loadAudiobook(audiobook)
        audio.resumePlayback()
    }

    /// One step up or down the player's speed list, clamped at the ends.
    static func stepSpeed(by step: Int) {
        let audio = GlobalAudioManager.shared
        let choices = PlaybackSpeed.choices
        let current = audio.getPlaybackRate()
        let index = choices.firstIndex { abs($0 - current) < 0.01 } ?? choices.firstIndex { $0 > current } ?? 0
        audio.setPlaybackRate(choices[min(max(index + step, 0), choices.count - 1)])
    }

    /// A bookmark at the playhead, named by its time. Shared by CarPlay and the keyboard.
    static func addBookmark() {
        let audio = GlobalAudioManager.shared
        guard let book = audio.currentAudiobook else { return }
        let time = audio.getCurrentTime()
        AudiobookManager.shared.createBookmark(
            for: book,
            at: time,
            title: String(
                format: NSLocalizedString("Bookmark at %@", comment: "Default bookmark title with time"),
                time.clockFormatted
            )
        )
    }

    static func perform(_ command: PlaybackCommand) async {
        guard await loadedBook() != nil else { return }
        let audio = GlobalAudioManager.shared
        switch command {
        case .toggle: audio.togglePlayback()
        case .skipForward: audio.skipForward()
        case .skipBackward: audio.skipBackward()
        }
    }
}
