import Foundation
import SwiftData

extension AudiobookManager {
    /// What an incoming file turns out to be, relative to what the library already holds.
    enum ImportMatch {
        /// The library already has this exact file. Importing it again would just make a
        /// second row pointing at `name_1.mp3`.
        case alreadyImported(AudiobookModel)
        /// The library remembers this book but its file is gone. The incoming file goes back
        /// where that book expects it, keeping its progress, bookmarks and chapters.
        case restores(AudiobookModel)
    }

    /// Matches an incoming file against the library by stored name.
    ///
    /// Names are unique inside the library folder — the copy step renames collisions — so a
    /// stored name matching an incoming one means the same slot, not a coincidence.
    @MainActor
    func match(for url: URL, size: Int64) -> ImportMatch? {
        let name = url.lastPathComponent
        for book in audiobooks {
            guard let existing = book.resolvedFileURL, existing.lastPathComponent == name else { continue }
            guard FileManager.default.fileExists(atPath: existing.path) else {
                return .restores(book)
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: existing.path)
            if attributes?[.size] as? Int64 == size {
                return .alreadyImported(book)
            }
        }
        return nil
    }

    /// Puts a re-picked file back where a library entry expects it, rather than importing a copy.
    /// Returns false when the file could not be written, so the caller falls through to a plain import.
    nonisolated func restore(_ url: URL, to destination: URL) async -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try streamCopyFile(from: url, to: destination)
            destination.disableFileProtection()
            Log.library.debug("🔗 AudiobookManager: Restored missing file for \(destination.lastPathComponent)")
            return true
        } catch {
            Log.library.error("❌ AudiobookManager: Could not restore \(destination.lastPathComponent): \(error)")
            return false
        }
    }

    /// Handles an incoming file that the library already knows about.
    /// Returns true when the file needs no further import.
    /// Stays on the main actor: `ImportMatch` carries a SwiftData model, which must never
    /// leave it. The one blocking call left here is a `stat`; the copy itself is `nonisolated`.
    @MainActor
    func resolveExistingEntry(for url: URL) async -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? Int64 ?? -1
        guard let match = match(for: url, size: size) else { return false }

        switch match {
        case .alreadyImported(let book):
            Log.library.debug("↩️ AudiobookManager: \(url.lastPathComponent) is already in the library, skipping")
            importBatch.append(book)
            return true
        case .restores(let book):
            guard let destination = book.resolvedFileURL,
                  await restore(url, to: destination)
            else { return false }
            importBatch.append(book)
            fetchAudiobooks()
            return true
        }
    }
}
