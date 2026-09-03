import Foundation
import AVFoundation

extension AudiobookPlayer {
    /// Works out the book's timeline. Runs off the main actor: it touches the file system and,
    /// in the fallback path, loads asset durations.
    nonisolated static func makeTracks(
        at url: URL,
        fallbackDuration: TimeInterval
    ) async -> [AudiobookTrack] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }

        guard isDirectory.boolValue else {
            let duration = await assetDuration(of: url) ?? fallbackDuration
            return [AudiobookTrack(url: url, start: 0, duration: duration)]
        }

        if let fromManifest = tracksFromManifest(in: url) {
            return fromManifest
        }
        return await tracksFromDirectoryListing(in: url)
    }

    /// The import writes `audiobook_manifest.json` with a duration per chapter file, which is
    /// the same data the stored chapters were built from — so it alone defines the timeline and
    /// nothing has to assume the chapter rows and the files line up by index.
    private nonisolated static func tracksFromManifest(in folder: URL) -> [AudiobookTrack]? {
        let manifestURL = folder.appendingPathComponent("audiobook_manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = manifest["chapters"] as? [[String: Any]] else {
            return nil
        }

        var tracks: [AudiobookTrack] = []
        var start: TimeInterval = 0
        for entry in entries {
            guard let fileName = entry["fileName"] as? String else { continue }
            let fileURL: URL
            do {
                // Containment only: despite the name, `existingFileURL` does not check that the
                // file is there, so the manifest can still name a chapter that was never copied.
                fileURL = try SafeImportPath.existingFileURL(for: fileName, inside: folder)
            } catch {
                Log.audio.warning("⚠️ AudiobookPlayer: Chapter path rejected: \(fileName)")
                continue
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Log.audio.warning("⚠️ AudiobookPlayer: Chapter file missing: \(fileName)")
                continue
            }
            let duration = entry["duration"] as? TimeInterval ?? 0
            guard duration > 0 else {
                Log.audio.warning("⚠️ AudiobookPlayer: Chapter has no duration: \(fileName)")
                continue
            }
            tracks.append(AudiobookTrack(url: fileURL, start: start, duration: duration))
            start += duration
        }
        return tracks.isEmpty ? nil : tracks
    }

    /// No manifest: sort the audio files by name and measure them. The old engine skipped the
    /// measuring and gave every chapter a start time of zero, so positions past chapter one
    /// were wrong.
    private nonisolated static func tracksFromDirectoryListing(in folder: URL) async -> [AudiobookTrack] {
        let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "flac", "aiff", "aif"]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }
        let files = contents
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var tracks: [AudiobookTrack] = []
        var start: TimeInterval = 0
        for file in files {
            guard let duration = await assetDuration(of: file), duration > 0 else { continue }
            tracks.append(AudiobookTrack(url: file, start: start, duration: duration))
            start += duration
        }
        return tracks
    }

    nonisolated static func assetDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds,
              seconds.isFinite, seconds > 0 else {
            return nil
        }
        return seconds
    }
}
