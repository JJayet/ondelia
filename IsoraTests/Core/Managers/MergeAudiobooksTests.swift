import Foundation
import Testing
@testable import Isora

@MainActor
struct MergeAudiobooksTests {
    private var audiobooksDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audiobooks")
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
        let prefix = UUID().uuidString
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let sources = try makeSources(manager, prefix: prefix)
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

    @Test("A single book is never merged, and nothing on disk moves")
    func mergeRefusesASingleBook() async throws {
        let prefix = UUID().uuidString
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let sources = try makeSources(manager, prefix: prefix)
        defer { for path in sources.compactMap(\.fileURL) { try? FileManager.default.removeItem(atPath: path) } }

        let merged = await manager.mergeAudiobooks([sources[0]], title: "Merged \(prefix)")

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
