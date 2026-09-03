import Foundation
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
