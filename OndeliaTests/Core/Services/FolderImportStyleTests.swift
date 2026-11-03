import Foundation
import Testing
import UIKit
@testable import Isora

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

    @Test("Audio files are filtered by extension and sorted the way Finder sorts them")
    func audioFilesFiltersAndSorts() throws {
        let folder = try makeFolder(files: ["02.mp3", "01.M4B", "cover.jpg", "notes.txt", "10.opus", "03.flac"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let names = FolderImporter.audioFiles(in: folder).map(\.lastPathComponent)

        // "10" sorts after "03", which a plain string compare gets wrong.
        #expect(names == ["01.M4B", "02.mp3", "03.flac", "10.opus"])
    }

    @Test("Audio files in subfolders are found and keep their subfolder")
    func audioFilesRecurseIntoSubfolders() throws {
        let folder = try makeFolder(files: ["00 - intro.mp3"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let disc = folder.appendingPathComponent("Disc 1", isDirectory: true)
        try FileManager.default.createDirectory(at: disc, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: disc.appendingPathComponent("01.mp3"))

        let found = FolderImporter.audioFiles(in: folder)

        #expect(found.map { FolderImporter.relativePath(of: $0, in: folder) } == ["00 - intro.mp3", "Disc 1/01.mp3"])
    }

    @Test("A folder describing its own layout is never ambiguous")
    func structuredFoldersAreNotAmbiguous() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let plain = try makeFolder(files: ["01.mp3", "02.mp3"])
        let withJson = try makeFolder(files: ["01.mp3", "02.mp3", "complete.json"])
        let withCue = try makeFolder(files: ["01.mp3", "02.mp3"])
        let twoCues = try makeFolder(files: ["01.mp3", "02.mp3"])
        defer { for folder in [plain, withJson, withCue, twoCues] { try? FileManager.default.removeItem(at: folder) } }
        try Data("FILE \"01.mp3\" MP3\n".utf8).write(to: withCue.appendingPathComponent("book.cue"))
        for name in ["01", "02"] {
            try Data("FILE \"\(name).mp3\" MP3\n".utf8).write(to: twoCues.appendingPathComponent("\(name).cue"))
        }

        #expect(manager.hasStructuredLayout(plain) == false)
        #expect(manager.hasStructuredLayout(withJson))
        #expect(manager.hasStructuredLayout(withCue))
        // One sheet per part is several books, not one CUE book: importing only the first lost the rest.
        #expect(manager.hasStructuredLayout(twoCues) == false)
    }

    @Test("A folder holding one audio file imports it with its own tags, not the folder's name")
    func singleFileFolderImportsTheFile() async throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let folder = try makeFolder(files: [])
        defer { try? FileManager.default.removeItem(at: folder) }
        let sample = try #require(Bundle(for: TestBundleAnchor.self).url(forResource: "sample", withExtension: "m4a"))
        try FileManager.default.copyItem(at: sample, to: folder.appendingPathComponent("Dune.m4a"))

        await manager.importAudiobookFolder(from: folder)

        let book = try #require(manager.importBatch.first)
        defer { if let url = book.resolvedFileURL { try? FileManager.default.removeItem(at: url) } }
        // The folder path import stored the folder and titled the book after it.
        #expect(book.fileURL?.hasSuffix(".m4a") == true)
        #expect(book.title != folder.lastPathComponent)
        #expect(book.duration > 0)
    }

    @Test("An unreadable audio file is reported, not imported as an empty book")
    func unreadableFileIsReported() async throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let folder = try makeFolder(files: ["broken.mp3"])
        defer { try? FileManager.default.removeItem(at: folder) }

        await manager.importAudiobook(from: folder.appendingPathComponent("broken.mp3"))

        #expect(manager.importBatch.isEmpty)
        #expect(manager.importErrorMessage != nil)
    }

    @Test("A multi-file pick from one folder is ambiguous, anything else is not")
    func commonAudioFolderDetection() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let folder = try makeFolder(files: ["01.mp3", "02.mp3", "notes.txt"])
        let other = try makeFolder(files: ["03.mp3"])
        defer { for url in [folder, other] { try? FileManager.default.removeItem(at: url) } }
        let files = ["01.mp3", "02.mp3"].map { folder.appendingPathComponent($0) }

        #expect(manager.commonAudioFolder(of: files) == folder.standardizedFileURL)
        // A stray non-audio pick says nothing about the audio, so it does not disqualify the folder.
        #expect(manager.commonAudioFolder(of: files + [folder.appendingPathComponent("notes.txt")]) == folder.standardizedFileURL)
        // A lone file, files from two folders, and the folders themselves all stay unambiguous.
        #expect(manager.commonAudioFolder(of: [files[0]]) == nil)
        #expect(manager.commonAudioFolder(of: files + [other.appendingPathComponent("03.mp3")]) == nil)
        #expect(manager.commonAudioFolder(of: [folder, other]) == nil)
    }

    @Test("Files staged separately by a file provider are still one multi-file pick")
    func providerStagedFilesAreStillAMultiFilePick() {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        // What a real pick off a file provider looks like: one numbered container per file, so
        // there is no shared parent to key the merge offer off.
        let root = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage")
        let files = [
            ("f104399954361", "101 - Opening Credits.mp3"),
            ("f104399970043", "102 - Epigrah (I).mp3"),
            ("f104399952513", "103 - Prologue.mp3")
        ].map { root.appendingPathComponent($0.0, isDirectory: true).appendingPathComponent($0.1) }

        #expect(manager.isMultiFileAudioPick(files))
        // No shared folder to name it after; the album tag has to supply the title.
        #expect(manager.commonAudioFolder(of: files) == nil)
    }

    @Test("A lone file or a mixed pick is not a multi-file pick")
    func singleAndMixedPicksAreNotOffered() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let folder = try makeFolder(files: ["01.mp3", "02.mp3"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = ["01.mp3", "02.mp3"].map { folder.appendingPathComponent($0) }

        #expect(manager.isMultiFileAudioPick([files[0]]) == false)
        #expect(manager.isMultiFileAudioPick(files + [folder]) == false)
        #expect(manager.isMultiFileAudioPick(files))
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
}
