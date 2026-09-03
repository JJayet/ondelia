import Foundation
import os
import Testing
@testable import AudiobookReader

@MainActor
struct FileCopyTests {
    @Test("Streaming copy preserves every byte across multiple chunks")
    func streamingCopyPreservesBytes() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = directory.appendingPathComponent("source.bin")
        let destination = directory.appendingPathComponent("destination.bin")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let bytes = Data((0..<(512 * 1_024 + 137)).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        let manager = AudiobookManager(swiftDataController: .inMemory())

        try manager.streamCopyFile(from: source, to: destination)

        #expect(try Data(contentsOf: destination) == bytes)
        #expect(
            try fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int
                == bytes.count
        )
    }

    @Test("Copying a folder audiobook runs off the main actor and lands every byte")
    func folderCopyRunsOffTheMainActor() async throws {
        let fileManager = FileManager.default
        let source = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: source) }

        let names = ["01.mp3", "02.mp3"]
        let payloads = names.map { Data($0.utf8) }
        for (name, payload) in zip(names, payloads) {
            try payload.write(to: source.appendingPathComponent(name))
        }
        let folderAudiobook = FolderAudiobook(
            title: "Book",
            author: "Author",
            narrator: nil,
            totalDuration: 2,
            chapters: names.enumerated().map { index, name in
                FolderChapter(
                    title: name,
                    fileName: name,
                    duration: 1,
                    startTimeInBook: TimeInterval(index),
                    chapterNumber: index + 1,
                    fileSize: 1
                )
            },
            folderPath: source.path,
            coverImage: nil
        )
        let manager = AudiobookManager(swiftDataController: .inMemory())

        let onMainActor = OSAllocatedUnfairLock(initialState: [Bool]())
        let destination = await manager.copyFolderToDocuments(
            from: source,
            folderAudiobook: folderAudiobook,
            onFileCopied: { _, _ in
                let isMain = Thread.isMainThread
                onMainActor.withLock { $0.append(isMain) }
            }
        )

        let copied = try #require(destination)
        defer { try? fileManager.removeItem(at: copied) }
        for (name, payload) in zip(names, payloads) {
            #expect(try Data(contentsOf: copied.appendingPathComponent(name)) == payload)
        }
        // The copy loop blocked the main thread before it was made nonisolated.
        #expect(onMainActor.withLock { $0 } == [false, false])
    }

    @Test("Streaming copy reports a missing source and leaves no destination")
    func streamingCopyMissingSourceFails() {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent("destination.bin")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let manager = AudiobookManager(swiftDataController: .inMemory())

        #expect(throws: (any Error).self) {
            try manager.streamCopyFile(
                from: directory.appendingPathComponent("missing.bin"),
                to: destination
            )
        }
        #expect(!fileManager.fileExists(atPath: destination.path))
    }
}
