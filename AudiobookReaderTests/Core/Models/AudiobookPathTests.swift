import Foundation
import Testing
@testable import AudiobookReader

@MainActor
struct AudiobookPathTests {
    private let staleContainer = "/var/mobile/Containers/Data/Application/OLD-UUID/Documents/Audiobooks/Dune/01.mp3"

    @Test("A library file is stored relative and resolves back to the same place")
    func libraryFilesRoundTrip() {
        let url = AudiobookModel.libraryFolderURL.appendingPathComponent("Dune/01.mp3")

        let stored = AudiobookModel.storedPath(for: url)

        #expect(stored == "Dune/01.mp3")
        #expect(AudiobookModel(fileURL: stored).resolvedFileURL == url)
    }

    @Test("A file outside the library keeps its absolute path")
    func outsideFilesStayAbsolute() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loose.mp3")

        #expect(AudiobookModel.storedPath(for: url) == url.path)
        #expect(AudiobookModel.libraryRelativePath(for: url.path) == nil)
        #expect(AudiobookModel(fileURL: url.path).resolvedFileURL == URL(fileURLWithPath: url.path))
    }

    @Test("A path from a dead container is rewritten to resolve in this one")
    func stalePathsMigrate() {
        // This is what a reinstall or a restore from an iOS backup leaves behind: the container
        // UUID is gone, but the part of the path that matters still names the right file.
        let book = AudiobookModel(fileURL: staleContainer)

        #expect(book.migrateToRelativePath())
        #expect(book.fileURL == "Dune/01.mp3")
        #expect(book.resolvedFileURL == AudiobookModel.libraryFolderURL.appendingPathComponent("Dune/01.mp3"))
    }

    @Test("Migration leaves alone what it cannot improve")
    func migrationSkipsNonLibraryPaths() {
        let loose = AudiobookModel(fileURL: "/var/mobile/Containers/Data/Application/X/Documents/loose.mp3")
        let alreadyRelative = AudiobookModel(fileURL: "Dune/01.mp3")
        let empty = AudiobookModel(fileURL: nil)

        #expect(loose.migrateToRelativePath() == false)
        #expect(alreadyRelative.migrateToRelativePath() == false)
        #expect(empty.migrateToRelativePath() == false)
        #expect(alreadyRelative.fileURL == "Dune/01.mp3")
        #expect(empty.resolvedFileURL == nil)
    }

    @Test("A subfolder that repeats the library name is kept in the relative path")
    func nestedLibraryFolderKeepsItsSubfolders() {
        // "…/Documents/Audiobooks/Documents/Audiobooks/x.mp3" is legal on disk. Only the first
        // marker is the container's library folder; dropping the rest would resolve to the
        // wrong file.
        let nested = AudiobookModel.libraryFolderURL
            .appendingPathComponent("Documents/Audiobooks/x.mp3")

        #expect(AudiobookModel.storedPath(for: nested) == "Documents/Audiobooks/x.mp3")
        #expect(AudiobookModel(fileURL: AudiobookModel.storedPath(for: nested)).resolvedFileURL == nested)
    }
}
