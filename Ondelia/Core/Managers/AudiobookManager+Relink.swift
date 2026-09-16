import AVFoundation
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

    /// The library entry a just-copied folder fills: one that already points at that path, whose
    /// audio was missing until now. A synced book from another device, or a folder that was
    /// deleted from Files. The copy chose the path because nothing was there, so a matching row
    /// is that book and not a coincidence; the duration guards against a same-named stranger.
    @MainActor
    func entryAwaitingFolder(at localURL: URL, duration: TimeInterval) -> AudiobookModel? {
        let path = localURL.standardizedFileURL.path
        return audiobooks.first { book in
            guard book.resolvedFileURL?.standardizedFileURL.path == path else { return false }
            return book.duration <= 0 || abs(book.duration - duration) < 1
        }
    }

    /// Whether an incoming file is as long as the book claiming it, within a second.
    /// A book stored with no duration has nothing to check against, so the name has to do.
    nonisolated func duration(of url: URL, matches expected: TimeInterval) async -> Bool {
        guard expected > 0 else { return true }
        guard let measured = try? await AVURLAsset(url: url).load(.duration).seconds,
              measured.isFinite else { return false }
        return abs(measured - expected) < 1
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
            // The library copy is gone, so size cannot be compared and the name is the only
            // thing left — and two books can each hold a `chapter01.mp3`. Duration is the one
            // property of the incoming file the library still remembers, so a mismatch falls
            // through to a normal import rather than inheriting another book's progress.
            guard let destination = book.resolvedFileURL,
                  await duration(of: url, matches: book.duration),
                  await restore(url, to: destination)
            else { return false }
            importBatch.append(book)
            fetchAudiobooks()
            return true
        }
    }
}
