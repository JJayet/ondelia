import Foundation
import SwiftData
import Testing
@testable import Isora

/// Touches the real library folder, so it must not run alongside the other filesystem suites.
/// The unit-test target is configured non-parallel for the same reason.
@MainActor
struct RelinkTests {
    /// Real playable audio of a known length: matching a re-picked file measures its duration,
    /// so a text file standing in for audio measures as nothing at all.
    private func makeSource(named name: String, seconds: UInt32) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try UITestBootstrap.writeSilentWave(to: url, seconds: seconds)
        return url
    }

    /// Puts a file where the library expects this book's audio, so the entry counts as present.
    private func fill(_ destination: URL, copying source: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contentsOf: source).write(to: destination)
    }

    @Test("Re-picking a file whose library copy vanished restores it instead of duplicating")
    func missingFileIsRestored() async throws {
        let name = "\(UUID().uuidString).wav"
        let source = try makeSource(named: name, seconds: 30)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Ghost", fileURL: name, duration: 30, currentPosition: 30)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()
        let destination = try #require(book.resolvedFileURL)
        defer { try? FileManager.default.removeItem(at: destination) }
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)

        let handled = await manager.resolveExistingEntry(for: source)

        #expect(handled)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        // The entry is reused, so the listening position survives.
        #expect(try manager.swiftDataController.context.fetch(FetchDescriptor<AudiobookModel>()).count == 1)
        #expect(book.currentPosition == 30)
    }

    @Test("A file whose name matches a missing book but whose length does not is imported fresh")
    func missingFileIsNotRestoredFromADifferentRecording() async throws {
        let name = "\(UUID().uuidString).wav"
        let source = try makeSource(named: name, seconds: 5)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        // Same `chapter01.mp3` name, four hours of book: taking this file would hand a
        // stranger's recording the progress and bookmarks of the missing one.
        let book = AudiobookModel(title: "Ghost", fileURL: name, duration: 14_400, currentPosition: 900)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()
        let destination = try #require(book.resolvedFileURL)
        defer { try? FileManager.default.removeItem(at: destination) }

        #expect(await manager.resolveExistingEntry(for: source) == false)
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
        #expect(book.currentPosition == 900)
    }

    @Test("Importing a file the library already holds is skipped")
    func duplicateIsSkipped() async throws {
        let name = "\(UUID().uuidString).wav"
        let source = try makeSource(named: name, seconds: 10)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Already here", fileURL: name, duration: 10)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()
        let destination = try #require(book.resolvedFileURL)
        try fill(destination, copying: source)
        defer { try? FileManager.default.removeItem(at: destination) }

        #expect(await manager.resolveExistingEntry(for: source))
        #expect(manager.importBatch.count == 1)
    }

    @Test("A different file that happens to share a name is imported normally")
    func differentContentIsNotADuplicate() async throws {
        let name = "\(UUID().uuidString).wav"
        let source = try makeSource(named: name, seconds: 20)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let other = try makeSource(named: "other-\(name)", seconds: 3)
        defer { try? FileManager.default.removeItem(at: other.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Other", fileURL: name, duration: 3)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()
        let destination = try #require(book.resolvedFileURL)
        try fill(destination, copying: other)
        defer { try? FileManager.default.removeItem(at: destination) }

        #expect(await manager.resolveExistingEntry(for: source) == false)
    }
}

struct DatabaseBackupTests {
    @Test("A live store backs up as one openable file that still holds its rows")
    func storeBacksUpAsASingleConsistentFile() throws {
        let schema = Schema([
            AudiobookModel.self,
            BookmarkModel.self,
            ChapterModel.self,
            ChapterTranscriptionModel.self
        ])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("default.store")

        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = ModelContext(container)
        context.insert(AudiobookModel(title: "Worth keeping", duration: 60, currentPosition: 25))
        try context.save()

        let destination = try #require(DatabaseBackupService.backUp(storeURL: storeURL))
        defer { try? FileManager.default.removeItem(at: destination) }
        let copy = destination.appendingPathComponent("default.store")

        // The snapshot is complete inside this one file — the write-ahead log is folded in,
        // which copying default.store, -wal and -shm separately could not guarantee. (A -wal
        // sibling does appear afterwards: verifying the copy opens it, and opening writes one.)
        #expect(FileManager.default.fileExists(atPath: copy.path))

        let restored = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: copy)]
        )
        let books = try ModelContext(restored).fetch(FetchDescriptor<AudiobookModel>())
        #expect(books.count == 1)
        #expect(books.first?.currentPosition == 25)
    }

    @Test("A copy that cannot be opened is discarded rather than kept as a false safety net")
    func invalidStoreIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bogus = folder.appendingPathComponent("default.store")
        try Data("not a database".utf8).write(to: bogus)

        let before = (try? FileManager.default.contentsOfDirectory(
            at: DatabaseBackupService.backupsDirectory, includingPropertiesForKeys: nil
        ))?.count ?? 0

        #expect(DatabaseBackupService.backUp(storeURL: bogus) == nil)

        let after = (try? FileManager.default.contentsOfDirectory(
            at: DatabaseBackupService.backupsDirectory, includingPropertiesForKeys: nil
        ))?.count ?? 0
        #expect(after == before)
    }
}
