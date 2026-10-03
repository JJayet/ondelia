import Foundation
import SwiftData
import Testing
@testable import Isora

@MainActor
struct MergeAudiobooksTests {
    private var audiobooksDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("Audiobooks")
    }

    /// A fresh in-memory library holding the two sources of `makeSources`, and their file prefix.
    private func makeLibrary() throws -> (manager: AudiobookManager, sources: [AudiobookModel], prefix: String) {
        let prefix = UUID().uuidString
        let manager = AudiobookManager(swiftDataController: .inMemory())
        return (manager, try makeSources(manager, prefix: prefix), prefix)
    }

    private func removeFolder(of book: AudiobookModel) {
        if let url = book.resolvedFileURL { try? FileManager.default.removeItem(at: url) }
    }

    /// Two single-file books sitting where an import would have left them.
    private func makeSources(_ manager: AudiobookManager, prefix: String) throws -> [AudiobookModel] {
        try FileManager.default.createDirectory(at: audiobooksDirectory, withIntermediateDirectories: true)
        let context = manager.swiftDataController.context
        return try ["02.mp3", "01.mp3"].enumerated().map { index, name in
            let url = audiobooksDirectory.appendingPathComponent("\(prefix)-\(name)")
            try Data("x".utf8).write(to: url)
            let book = AudiobookModel(
                title: "Part \(name)",
                author: index == 0 ? "Unknown Author" : "Real Author",
                fileURL: url.path,
                duration: 60
            )
            context.insert(book)
            return book
        }
    }

    @Test("Merging folds the sources into one folder-backed book, in file name order")
    func mergeProducesOneBook() async throws {
        let (manager, sources, prefix) = try makeLibrary()
        let sourceURLs = sources.compactMap(\.resolvedFileURL)

        let merged = try #require(await manager.mergeAudiobooks(sources, title: "Merged \(prefix)"))
        let mergedURL = try #require(merged.resolvedFileURL)
        defer { try? FileManager.default.removeItem(at: mergedURL) }

        // Stored relative, so a new app container still finds it.
        #expect(merged.fileURL == "Merged \(prefix)")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: mergedURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(merged.duration == 120)
        // The first source carried the placeholder author, so the real one wins.
        #expect(merged.author == "Real Author")

        let chapters = merged.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        #expect(chapters.map(\.title) == ["Part 01.mp3", "Part 02.mp3"])
        #expect(chapters.map(\.startTime) == [0, 60])
        #expect(chapters.map(\.endTime) == [60, 120])

        // The manifest is what playback reads, so it has to name both files.
        let manifestURL = mergedURL.appendingPathComponent("audiobook_manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let manifestChapters = try #require(manifest?["chapters"] as? [[String: Any]])
        #expect(manifestChapters.compactMap { $0["fileName"] as? String } == ["\(prefix)-01.mp3", "\(prefix)-02.mp3"])
        for name in manifestChapters.compactMap({ $0["fileName"] as? String }) {
            #expect(FileManager.default.fileExists(atPath: mergedURL.appendingPathComponent(name).path))
        }

        // Sources are gone from disk and from the library.
        #expect(sourceURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(manager.audiobooks.count == 1)
    }

    @Test("Merging carries bookmarks, position and Collection membership onto the merged timeline")
    func mergeCarriesListenerState() async throws {
        let (manager, sources, prefix) = try makeLibrary()
        // Merge order is by file name: 01 becomes chapter 1 at 0 s, 02 chapter 2 at 60 s.
        let (second, first) = (try #require(sources.first), try #require(sources.last))
        first.isFinished = true
        second.currentPosition = 10
        let bookmark = BookmarkModel(title: "Quote", timestamp: 5)
        bookmark.audiobook = second
        let other = UUID()
        let shelf = CollectionModel(name: "Shelf", bookIDs: [other, second.id, first.id])
        manager.swiftDataController.context.insert(shelf)
        manager.fetchCollections()

        let merged = try #require(await manager.mergeAudiobooks(sources, title: "Merged \(prefix)"))
        defer { removeFolder(of: merged) }

        #expect(merged.currentPosition == 70)
        #expect(merged.isFinished == false)
        #expect(merged.bookmarks.map(\.timestamp) == [65])
        #expect(shelf.bookIDs == [other, merged.id])
    }

    @Test("A merge of Finished sources is Finished, without a new Finish in the log")
    func mergeOfFinishedSourcesIsFinished() async throws {
        let (manager, sources, prefix) = try makeLibrary()
        for source in sources { source.isFinished = true }

        let merged = try #require(await manager.mergeAudiobooks(sources, title: "Merged \(prefix)"))
        defer { removeFolder(of: merged) }

        #expect(merged.isFinished)
        #expect(merged.currentPosition == 120)
        let log = try manager.swiftDataController.context.fetch(FetchDescriptor<ListeningSessionModel>())
            + ReadingStatistics.shared.sessions
        #expect(!log.contains { $0.bookID == merged.id && $0.finishedBook })
    }

    @Test("The merged audiobook takes the first queued source's slot in Up Next")
    func mergeTakesTheFirstQueuedSlot() async throws {
        let (manager, sources, prefix) = try makeLibrary()
        let (second, first) = (try #require(sources.first), try #require(sources.last))
        let other = AudiobookModel(title: "Other", fileURL: nil)
        let queue = PlayQueue.shared
        for book in [other, second, first] { queue.append(book) }
        defer { for book in [other, second, first] { queue.remove(book) } }

        let merged = try #require(await manager.mergeAudiobooks(sources, title: "Merged \(prefix)"))
        defer {
            queue.remove(merged)
            removeFolder(of: merged)
        }

        let ours: Set = [other.id, second.id, first.id, merged.id]
        #expect(queue.bookIDs.filter(ours.contains) == [other.id, merged.id])
    }

    @Test("A merge that already synced from another device keeps its own state, applied once")
    func syncedMergeIsNotCarriedOverTwice() async throws {
        let (manager, sources, prefix) = try makeLibrary()
        let second = try #require(sources.first)
        second.currentPosition = 10
        BookmarkModel(title: "Source", timestamp: 5).audiobook = second
        // The other device's merge: same folder, same length, its own carried-over state.
        let synced = AudiobookModel(title: "Merged \(prefix)", author: "Real Author", fileURL: "Merged \(prefix)", duration: 120)
        synced.currentPosition = 90
        manager.swiftDataController.context.insert(synced)
        BookmarkModel(title: "Synced", timestamp: 65).audiobook = synced
        manager.fetchAudiobooks()

        let merged = try #require(await manager.mergeAudiobooks(sources, title: "Merged \(prefix)"))
        defer { removeFolder(of: merged) }

        #expect(merged.id == synced.id)
        #expect(merged.currentPosition == 90)
        #expect(merged.bookmarks.map(\.title) == ["Synced"])
        #expect(manager.audiobooks.count == 1)
    }

    @Test("The merged id takes the first source's slot, once")
    func replacingKeepsTheFirstSlot() {
        let (a, b, c, merged) = (UUID(), UUID(), UUID(), UUID())
        #expect([c, b, a].replacingSources([a, b], with: merged) == [c, merged])
        #expect([b, merged, a].replacingSources([a, b], with: merged) == [merged])
        #expect([c].replacingSources([a], with: merged) == [c])
    }

    @Test("A single book is never merged, and nothing on disk moves")
    func mergeRefusesASingleBook() async throws {
        let (manager, sources, prefix) = try makeLibrary()
        defer { for path in sources.compactMap(\.fileURL) { try? FileManager.default.removeItem(atPath: path) } }

        let merged = await manager.mergeAudiobooks([try #require(sources.first)], title: "Merged \(prefix)")

        #expect(merged == nil)
        #expect(manager.importErrorMessage != nil)
        #expect(sources.compactMap(\.fileURL).allSatisfy { FileManager.default.fileExists(atPath: $0) })
    }

    @Test("A folder-backed book cannot be merged")
    func folderBackedBooksAreNotMergeable() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let folder = audiobooksDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("01.mp3")
        try Data("x".utf8).write(to: file)

        #expect(manager.canMerge(AudiobookModel(fileURL: file.path)))
        #expect(manager.canMerge(AudiobookModel(fileURL: folder.path)) == false)
        #expect(manager.canMerge(AudiobookModel(fileURL: nil)) == false)
    }
}
