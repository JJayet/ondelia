import Foundation
import Intents

/// Serves the `INPlayMediaIntent` the system sends back when someone taps the app in the media
/// suggestions, or asks Siri to play a book.
///
/// Handled in the app process rather than in an Intents extension: the audio engine and the
/// library only exist here, so an extension would have to hand everything straight back anyway.
final class MediaIntentHandler: NSObject, INPlayMediaIntentHandling {

    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void
    ) {
        // A suggestion replays the donated intent, so the item it carries is already the answer.
        if let items = intent.mediaItems, !items.isEmpty {
            completion(INPlayMediaMediaItemResolutionResult.successes(with: items))
            return
        }

        // Pulled out before the hop: the intent's own types are not `Sendable`, its strings are.
        let identifier = intent.mediaSearch?.mediaIdentifier
        let name = intent.mediaSearch?.mediaName
        // The Intents framework hands back a plain completion block; taking it to the main
        // actor is exactly what it is for.
        nonisolated(unsafe) let finish = completion

        Task { @MainActor in
            guard let book = await PlaybackCommands.book(identifier: identifier, named: name) else {
                finish([.unsupported(forReason: .unsupportedMediaType)])
                return
            }
            finish(INPlayMediaMediaItemResolutionResult.successes(with: [Self.mediaItem(for: book)]))
        }
    }

    func handle(
        intent: INPlayMediaIntent,
        completion: @escaping (INPlayMediaIntentResponse) -> Void
    ) {
        let identifier = intent.mediaItems?.first?.identifier ?? intent.mediaSearch?.mediaIdentifier
        let name = intent.mediaSearch?.mediaName
        nonisolated(unsafe) let finish = completion

        Task { @MainActor in
            guard let book = await PlaybackCommands.book(identifier: identifier, named: name) else {
                finish(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
                return
            }
            PlaybackCommands.play(book)
            finish(INPlayMediaIntentResponse(code: .success, userActivity: nil))
        }
    }

    @MainActor
    private static func mediaItem(for audiobook: AudiobookModel) -> INMediaItem {
        INMediaItem(
            identifier: audiobook.id.uuidString,
            title: audiobook.title ?? AudiobookModel.unknownTitle,
            type: .audioBook,
            artwork: audiobook.coverImageData.map { INImage(imageData: $0) },
            artist: audiobook.author ?? AudiobookModel.unknownAuthor
        )
    }
}
