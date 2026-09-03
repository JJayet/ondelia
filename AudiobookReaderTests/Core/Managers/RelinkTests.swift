import Foundation
import SwiftData
import Testing
@testable import AudiobookReader

/// Touches the real library folder, so it must not run alongside the other filesystem suites.
/// The unit-test target is configured non-parallel for the same reason.
@MainActor
struct RelinkTests {
    private func makeSource(named name: String, bytes: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    @Test("Re-picking a file whose library copy vanished restores it instead of duplicating")
    func missingFileIsRestored() async throws {
        let name = "\(UUID().uuidString).mp3"
        let source = try makeSource(named: name, bytes: "audio")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Ghost", fileURL: name, duration: 42, currentPosition: 30)
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

    @Test("Importing a file the library already holds is skipped")
    func duplicateIsSkipped() async throws {
        let name = "\(UUID().uuidString).mp3"
        let source = try makeSource(named: name, bytes: "audio")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Already here", fileURL: name, duration: 42)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()
        let destination = try #require(book.resolvedFileURL)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }

        #expect(await manager.resolveExistingEntry(for: source))
        #expect(manager.importBatch.count == 1)
    }

    @Test("A different file that happens to share a name is imported normally")
    func differentContentIsNotADuplicate() async throws {
        let name = "\(UUID().uuidString).mp3"
        let source = try makeSource(named: name, bytes: "a much longer recording")
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Other", fileURL: name, duration: 42)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()
        let destination = try #require(book.resolvedFileURL)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("short".utf8).write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }

        #expect(await manager.resolveExistingEntry(for: source) == false)
    }
}

struct DatabaseBackupTests {
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
