import Foundation
import Testing
@testable import AudiobookReader

@MainActor
struct ImportMergePromptTests {
    private func makeFolder(files: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files { try Data("x".utf8).write(to: folder.appendingPathComponent(name)) }
        return folder
    }

    private func wait(for manager: AudiobookManager) async -> Bool {
        for _ in 0..<80 {
            if manager.mergePrompt != nil { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func makeBook(files: [String]) throws -> URL {
        try makeFolder(files: files)
    }

    @Test("Picking the files raises the merge prompt")
    func filePickRaisesPrompt() async throws {
        let folder = try makeBook(files: ["01.mp3", "02.mp3"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = AudiobookManager(swiftDataController: .inMemory())
        manager.handleImportRequest(urls: ["01.mp3", "02.mp3"].map { folder.appendingPathComponent($0) })
        #expect(await wait(for: manager), "no prompt; batch=\(manager.importBatch.count) title=\(String(describing: manager.pendingMergeTitle))")
    }

    @Test("A second import waits instead of wiping the first one's batch")
    func concurrentImportsAreSerialized() async throws {
        // Two imports in flight at once share `importBatch` and `pendingMergeTitle`, and the
        // second run resetting them under the first is what silently swallowed the merge offer.
        let first = try makeBook(files: ["01.mp3", "02.mp3"])
        let second = try makeBook(files: ["03.mp3", "04.mp3"])
        defer { for url in [first, second] { try? FileManager.default.removeItem(at: url) } }
        let manager = AudiobookManager(swiftDataController: .inMemory())

        manager.handleImportRequest(urls: ["01.mp3", "02.mp3"].map { first.appendingPathComponent($0) })
        manager.handleImportRequest(urls: ["03.mp3", "04.mp3"].map { second.appendingPathComponent($0) })

        #expect(manager.pendingImports.count == 1, "the second import should have queued")
        #expect(await wait(for: manager))
        #expect(manager.mergePrompt?.suggestedTitle == first.lastPathComponent)
        #expect(manager.mergePrompt?.bookCount == 2)

        // Answering releases the gate, and the queued import then gets its own offer.
        manager.mergePrompt?.respond(false)
        #expect(await wait(for: manager))
        #expect(manager.mergePrompt?.suggestedTitle == second.lastPathComponent)
        #expect(manager.mergePrompt?.bookCount == 2)
    }

    @Test("Files are imported in file name order whatever order they arrive in")
    func importsFollowFileNameOrder() async throws {
        let folder = try makeBook(files: ["101 - a.mp3", "102 - b.mp3", "103 - c.mp3"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = AudiobookManager(swiftDataController: .inMemory())

        // Handed over in the order a directory listing or a picker might produce.
        manager.handleImportRequest(urls: ["103 - c.mp3", "101 - a.mp3", "102 - b.mp3"].map {
            folder.appendingPathComponent($0)
        })
        #expect(await wait(for: manager))

        // dateAdded is the only record of sequence: titles come from file metadata.
        // Names can gain a `_1` suffix when the library already holds that file name, so compare
        // the numbering rather than the whole name.
        let order = manager.audiobooks
            .sorted { $0.dateAdded < $1.dateAdded }
            .compactMap { $0.fileURL.map { String($0.prefix(3)) } }
        #expect(order == ["101", "102", "103"])
    }

    @Test("A pick with no shared folder still raises the merge prompt")
    func providerStyledPickRaisesPrompt() async throws {
        // Each file in its own directory, the way a file provider hands them over. The offer has
        // to survive that, because it is the common case for anything not stored locally.
        let folders = try (0..<3).map { _ in try makeFolder(files: ["chapter.mp3"]) }
        defer { for url in folders { try? FileManager.default.removeItem(at: url) } }
        let manager = AudiobookManager(swiftDataController: .inMemory())

        manager.handleImportRequest(urls: folders.map { $0.appendingPathComponent("chapter.mp3") })

        #expect(await wait(for: manager), "no prompt; batch=\(manager.importBatch.count) title=\(String(describing: manager.pendingMergeTitle))")
        #expect(manager.mergePrompt?.bookCount == 3)
        // No shared folder and no album tag on these stubs, so it falls back to the first title.
        #expect(manager.mergePrompt?.suggestedTitle.isEmpty == false)
    }

    @Test("Picking the folder raises the merge prompt")
    func folderPickRaisesPrompt() async throws {
        let folder = try makeBook(files: ["01.mp3", "02.mp3"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = AudiobookManager(swiftDataController: .inMemory())
        manager.handleImportRequest(urls: [folder])
        #expect(await wait(for: manager), "no prompt; batch=\(manager.importBatch.count) title=\(String(describing: manager.pendingMergeTitle))")
    }
}
