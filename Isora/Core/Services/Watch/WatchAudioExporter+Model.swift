import AVFoundation
import Foundation

extension WatchAudioExporter {

    /// Turns a stored book plus one of its chapters into something `export(_:to:)` can read.
    ///
    /// A single-file book gives a time range on the one file; a folder book gives the chapter's
    /// own file, found the same way `AudiobookPlayer+Tracks` finds it — the manifest first,
    /// because the chapter rows and the files on disk do not have to line up by index.
    static func exportSource(for book: AudiobookModel, chapter: ChapterModel) throws -> ExportSource {
        guard let url = book.resolvedFileURL else { throw ExportError.sourceUnavailable }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExportError.sourceUnavailable
        }

        guard isDirectory.boolValue else {
            guard chapter.endTime > chapter.startTime else {
                throw ExportError.chapterFileNotFound(Int(chapter.chapterNumber))
            }
            let range = CMTimeRange(
                start: CMTime(seconds: chapter.startTime, preferredTimescale: 600),
                end: CMTime(seconds: chapter.endTime, preferredTimescale: 600)
            )
            return ExportSource(fileURL: url, timeRange: range)
        }

        let index = book.sortedChapters.firstIndex { $0.id == chapter.id } ?? 0
        let number = Int(chapter.chapterNumber)
        guard let file = manifestFile(in: url, number: number, index: index)
            ?? listingFile(in: url, index: index) else {
            throw ExportError.chapterFileNotFound(number)
        }
        return ExportSource(fileURL: file)
    }

    /// The manifest the import writes. Matched on `chapterNumber` when it is there, on position
    /// otherwise, since older manifests only carry the order.
    private static func manifestFile(in folder: URL, number: Int, index: Int) -> URL? {
        let manifestURL = folder.appendingPathComponent("audiobook_manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = manifest["chapters"] as? [[String: Any]] else {
            return nil
        }
        let entry = entries.first { ($0["chapterNumber"] as? Int) == number }
            ?? (entries.indices.contains(index) ? entries[index] : nil)
        guard let fileName = entry?["fileName"] as? String,
              let fileURL = try? SafeImportPath.containedFileURL(for: fileName, inside: folder),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    /// No manifest: the audio files sorted by name, taken by position.
    private static func listingFile(in folder: URL, index: Int) -> URL? {
        let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "flac", "aiff", "aif"]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return nil
        }
        let files = contents
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard files.indices.contains(index) else { return nil }
        return files[index]
    }
}
