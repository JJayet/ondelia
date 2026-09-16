import Foundation
import Testing
@testable import Isora

struct SafeImportPathTests {
    @Test("Normal relative paths are preserved and nested inside the root")
    func normalRelativePath() throws {
        let root = URL(fileURLWithPath: "/tmp/audiobooks", isDirectory: true)

        let result = try SafeImportPath.resolvedURL(for: "disc 1/chapter01.mp3", inside: root)

        #expect(result.path == "/tmp/audiobooks/disc 1/chapter01.mp3")
    }

    @Test(
        "Unsafe import paths are rejected",
        arguments: [
            "../escape.mp3",
            "disc/../../escape.mp3",
            "/absolute/book.mp3",
            "C:\\books\\book.mp3",
            "disc//book.mp3"
        ]
    )
    func unsafePathsAreRejected(path: String) {
        #expect(throws: (any Error).self) {
            try SafeImportPath.resolvedURL(
                for: path,
                inside: URL(fileURLWithPath: "/tmp/audiobooks", isDirectory: true)
            )
        }
    }

    @Test("A symlink inside the root cannot resolve to a file outside it")
    func symlinkEscapeIsRejected() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = fileManager.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        let link = root.appendingPathComponent("linked.mp3")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outside)
        }

        #expect(throws: (any Error).self) {
            try SafeImportPath.containedFileURL(for: "linked.mp3", inside: root)
        }
    }
}
