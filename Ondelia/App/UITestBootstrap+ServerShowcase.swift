#if DEBUG
import Foundation
import SwiftData

// MARK: - App Store screenshots from a real shelf
//
// `--seed-showcase` with SHOWCASE_SERVER, SHOWCASE_USER and SHOWCASE_PASSWORD in the launch
// environment: the shelf is the first book of each of the account's AudiobookShelf collections,
// streamed with their real covers, chapters and metadata, instead of generated books. Progress
// and the fortnight of listening are still made up, and never sent to the server.
extension UITestBootstrap {
    struct ShowcaseAccount {
        let server: String
        let username: String
        let password: String
    }

    /// Progress per shelf slot, in shelf order: some underway, one finished, some untouched.
    private static let showcaseProgress: [Double] = [0.42, 0.78, 0.15, 1, 0.6, 0, 0.3, 0]

    static var showcaseAccount: ShowcaseAccount? {
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["SHOWCASE_SERVER"], !server.isEmpty,
              let username = environment["SHOWCASE_USER"], let password = environment["SHOWCASE_PASSWORD"]
        else { return nil }
        return ShowcaseAccount(server: server, username: username, password: password)
    }

    /// Runs once the store is loaded: the books are made by the streaming code, which needs it.
    static func seedShowcase(from account: ShowcaseAccount) async {
        await SwiftDataController.shared.whenLoaded()
        let service = AudiobookShelfService.shared
        do {
            try await service.signIn(server: account.server, username: account.username, password: account.password)
            guard let primary = service.primary, let (server, token) = service.session(for: primary) else { return }
            // The UI tests keep servers off the shelf; streamed books are only shown with theirs.
            service.setShowsInLibrary(true, for: primary.id)
            var items: [AudiobookShelfAPI.Item] = []
            for library in try await AudiobookShelfAPI.libraries(server: server, token: token) {
                for collection in try await AudiobookShelfAPI.collections(server: server, token: token, library: library.id) {
                    // A book in several collections stands for the first; the next one gets its next book.
                    if let book = collection.books?.first(where: { book in !items.contains { $0.id == book.id } }) {
                        items.append(book)
                    }
                }
            }

            let context = SwiftDataController.shared.context
            let now = Date()
            for (index, item) in items.enumerated() {
                let book = try await service.libraryBook(for: item)
                let progress = showcaseProgress[index % showcaseProgress.count]
                book.currentPosition = book.duration * progress
                book.isFinished = progress >= 1
                book.dateAdded = now.addingTimeInterval(Double(-index) * 86_400 * 3)
                book.lastPlayed = progress > 0 ? now.addingTimeInterval(Double(-index) * 3_600 * 5) : .distantPast
                seedListening(to: book, index: index, progress: progress, now: now, context: context)
            }
            try context.save()
            AudiobookManager.shared.fetchAudiobooks()
            ReadingStatistics.shared.reload()
        } catch {
            Log.library.error("Showcase: the server shelf failed: \(error.localizedDescription)")
        }
    }
}
#endif
