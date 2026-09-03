import Foundation
import Testing
import UIKit
@testable import AudiobookReader

@MainActor
struct FolderImportStyleTests {
    private func makeFolder(files: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    @Test("Audio files are filtered by extension and sorted by name")
    func audioFilesFiltersAndSorts() throws {
        let folder = try makeFolder(files: ["02.mp3", "01.M4B", "cover.jpg", "notes.txt", "03.flac"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let names = FolderImporter.audioFiles(in: folder).map(\.lastPathComponent)

        #expect(names == ["01.M4B", "02.mp3", "03.flac"])
    }

    @Test("A folder describing its own layout is never ambiguous")
    func structuredFoldersAreNotAmbiguous() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let plain = try makeFolder(files: ["01.mp3", "02.mp3"])
        let withJson = try makeFolder(files: ["01.mp3", "02.mp3", "complete.json"])
        let withCue = try makeFolder(files: ["01.mp3", "02.mp3", "book.cue"])
        defer { for folder in [plain, withJson, withCue] { try? FileManager.default.removeItem(at: folder) } }

        #expect(manager.hasStructuredLayout(plain) == false)
        #expect(manager.hasStructuredLayout(withJson))
        #expect(manager.hasStructuredLayout(withCue))
    }

    @Test("A multi-file pick from one folder is ambiguous, anything else is not")
    func commonAudioFolderDetection() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let folder = try makeFolder(files: ["01.mp3", "02.mp3", "notes.txt"])
        let other = try makeFolder(files: ["03.mp3"])
        defer { for url in [folder, other] { try? FileManager.default.removeItem(at: url) } }
        let files = ["01.mp3", "02.mp3"].map { folder.appendingPathComponent($0) }

        #expect(manager.commonAudioFolder(of: files) == folder.standardizedFileURL)
        // A lone file, a non-audio file, files from two folders, and the folder itself all stay unambiguous.
        #expect(manager.commonAudioFolder(of: [files[0]]) == nil)
        #expect(manager.commonAudioFolder(of: files + [folder.appendingPathComponent("notes.txt")]) == nil)
        #expect(manager.commonAudioFolder(of: files + [other.appendingPathComponent("03.mp3")]) == nil)
        #expect(manager.commonAudioFolder(of: [folder, other]) == nil)
    }

    @Test("Files on an unreadable file provider are still recognised as one folder")
    func commonAudioFolderNeedsNoFileAccess() {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        // Nothing exists at these paths, standing in for a provider whose scope is not claimed yet.
        let folder = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/Provider/Book", isDirectory: true)
        let files = ["101 - Opening Credits.mp3", "102 - Epigraph (I).mp3"]
            .map { folder.appendingPathComponent($0) }

        #expect(manager.commonAudioFolder(of: files) == folder.standardizedFileURL)
        #expect(manager.commonAudioFolder(of: files + [folder]) == nil)
    }

    @Test("One cover picked at the end of a split import covers the whole batch")
    func coverBatchSharesPickedImage() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let context = manager.swiftDataController.context
        let books = (0..<3).map { index -> AudiobookModel in
            let book = AudiobookModel(title: "Chapter \(index)")
            context.insert(book)
            return book
        }
        manager.coverBatch = books

        manager.updateCoverImage(for: books[0], with: UIImage(systemName: "book")!)

        #expect(books.allSatisfy { $0.coverImageData != nil })
        #expect(manager.coverBatch.isEmpty)
    }
}
