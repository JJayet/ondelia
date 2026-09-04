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
