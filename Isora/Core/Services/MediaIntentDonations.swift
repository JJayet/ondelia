import Foundation
import Intents
import SwiftData

/// What makes the app eligible for the system's media suggestions — the row of covers in
/// Control Center, on the Lock Screen and in Search.
///
/// Two halves, both required: a media user context that says this is an audio app with a
/// library, and one `INPlayMediaIntent` donation per listening session, which is what the
/// system ranks. Placement is the system's call; donating only makes the app a candidate.
@MainActor
enum MediaIntentDonations {
    /// The last donation, so one listening session donates once rather than on every unpause —
    /// while a session picked up hours later still counts as the fresh play that it is.
    private static var lastDonation: (bookID: UUID, at: Date)?
    private static let sessionGap: TimeInterval = 30 * 60

    /// Donate the book being played. Called whenever playback starts.
    static func donatePlayback(of audiobook: AudiobookModel) {
        if let last = lastDonation,
           last.bookID == audiobook.id,
           Date().timeIntervalSince(last.at) < sessionGap {
            return
        }
        lastDonation = (audiobook.id, Date())

        let item = INMediaItem(
            identifier: audiobook.id.uuidString,
            title: audiobook.title ?? AudiobookModel.unknownTitle,
            type: .audioBook,
            artwork: audiobook.coverImageData.map { INImage(imageData: $0) },
            artist: audiobook.author ?? AudiobookModel.unknownAuthor
        )
        let intent = INPlayMediaIntent(
            mediaItems: [item],
            mediaContainer: nil,
            playShuffled: false,
            playbackRepeatMode: .none,
            resumePlayback: true,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: INMediaSearch(
                mediaType: .audioBook,
                sortOrder: .unknown,
                mediaName: audiobook.title,
                artistName: audiobook.author,
                albumName: nil,
                genreNames: nil,
                moodNames: nil,
                releaseDate: nil,
                reference: .unknown,
                mediaIdentifier: audiobook.id.uuidString
            )
        )

        let interaction = INInteraction(intent: intent, response: nil)
        // The identifier is the book, so a re-donation replaces the old entry rather than
        // stacking another copy of the same book in the suggestions.
        interaction.identifier = audiobook.id.uuidString
        interaction.donate { error in
            guard let error else { return }
            Log.audio.error("Failed to donate the playback intent: \(error.localizedDescription)")
        }
    }

    /// Tells the system this is a media app and how much it holds. Cheap, so it runs whenever
    /// the app becomes active rather than trying to spot the moment the library changed.
    static func refreshUserContext() {
        let store = SwiftDataController.shared
        guard store.isLoaded,
              let count = try? store.context.fetchCount(FetchDescriptor<AudiobookModel>()) else { return }

        let context = INMediaUserContext()
        // Nothing to subscribe to: the library is whatever the listener imported.
        context.subscriptionStatus = .notSubscribed
        context.numberOfLibraryItems = count
        context.becomeCurrent()
    }
}
