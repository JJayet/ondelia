import Foundation

/// Everything the watch does to `Documents/Audiobooks/<bookID>/`: naming, inventory, the
/// playback manifest and deletion. Pure Foundation and nonisolated so the `WCSessionDelegate`
/// callbacks — which must move an incoming file *before* they return — can use it directly.
enum WatchLibraryDisk {
    static let manifestName = "audiobook_manifest.json"

    /// One folder per book, named by its id. `AudiobookModel.fileURL` stores that same id, so
    /// `resolvedFileURL` lands here.
    static func bookFolder(_ bookID: UUID) -> URL {
        AudiobookModel.libraryFolderURL.appendingPathComponent(bookID.uuidString)
    }

    static func chapterFileName(_ number: Int) -> String {
        "chapter-\(number).m4a"
    }

    static func chapterURL(bookID: UUID, number: Int) -> URL {
        bookFolder(bookID).appendingPathComponent(chapterFileName(number))
    }

    /// A cover can land before the snapshot that creates the book row — covers are sent once and
    /// never again — so it is kept here and read back when the row finally exists.
    static func coverURL(bookID: UUID) -> URL {
        bookFolder(bookID).appendingPathComponent("cover.jpg")
    }

    static func writeCover(_ data: Data, bookID: UUID) {
        let url = coverURL(bookID: bookID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            Log.sync.error("❌ WatchLibraryDisk: cover write failed: \(error.localizedDescription)")
        }
    }

    static func cover(bookID: UUID) -> Data? {
        try? Data(contentsOf: coverURL(bookID: bookID))
    }

    // MARK: - Inventory

    /// Chapter numbers whose audio is actually on this watch, ascending.
    static func chaptersOnDisk(bookID: UUID) -> [Int] {
        let folder = bookFolder(bookID)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return names.compactMap(chapterNumber(fromFileName:)).sorted()
    }

    /// `chapter-14.m4a` → 14. Nil for anything else in the folder, the manifest included.
    static func chapterNumber(fromFileName name: String) -> Int? {
        guard name.hasPrefix("chapter-"), name.hasSuffix(".m4a") else { return nil }
        return Int(name.dropFirst("chapter-".count).dropLast(".m4a".count))
    }

    static func byteCount(bookID: UUID, number: Int) -> Int64 {
        let url = chapterURL(bookID: bookID, number: number)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// Total bytes of audio held on the watch, across every book.
    static func bytesOnDisk() -> Int64 {
        let root = AudiobookModel.libraryFolderURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Book folders that currently hold at least one chapter.
    static func bookIDsWithContent() -> [UUID] {
        let root = AudiobookModel.libraryFolderURL
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return names.compactMap(UUID.init(uuidString:)).filter { !chaptersOnDisk(bookID: $0).isEmpty }
    }

    // MARK: - Manifest

    /// The manifest lists **every** chapter of the book, present on disk or not, because
    /// `AudiobookPlayer+Tracks` builds the timeline from it and keeps a gap where a file is
    /// missing. Drop the absent ones and every later chapter would start in the wrong place.
    static func manifestData(chapters: [ChapterSummary]) throws -> Data {
        let entries: [[String: Any]] = chapters.sorted { $0.number < $1.number }.map { chapter in
            [
                "title": chapter.title ?? "",
                "fileName": chapterFileName(chapter.number),
                "duration": max(chapter.end - chapter.start, 0),
                "startTime": chapter.start,
                "chapterNumber": chapter.number
            ]
        }
        return try JSONSerialization.data(withJSONObject: ["chapters": entries])
    }

    static func writeManifest(bookID: UUID, chapters: [ChapterSummary]) {
        let folder = bookFolder(bookID)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try manifestData(chapters: chapters).write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        } catch {
            Log.sync.error("❌ WatchLibraryDisk: manifest write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    static func deleteChapter(bookID: UUID, number: Int) {
        try? FileManager.default.removeItem(at: chapterURL(bookID: bookID, number: number))
    }

    static func deleteBook(_ bookID: UUID) {
        try? FileManager.default.removeItem(at: bookFolder(bookID))
    }

    static func deleteEverything() {
        for bookID in allBookFolders() { deleteBook(bookID) }
    }

    private static func allBookFolders() -> [UUID] {
        let root = AudiobookModel.libraryFolderURL
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap(UUID.init(uuidString:))
    }

    // MARK: - Last write wins

    /// The one progress rule both sides share: a remote write only lands when it is newer than
    /// what is stored here. A remote write with no timestamp never wins; a local row with no
    /// timestamp always loses.
    static func shouldApplyRemotePosition(remote: Date?, local: Date?) -> Bool {
        guard let remote else { return false }
        return remote > (local ?? .distantPast)
    }
}
