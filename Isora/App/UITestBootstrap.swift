#if DEBUG
import Foundation
import SwiftData
import SwiftUI

@MainActor
enum UITestBootstrap {
    /// Applies the type size a UI test asked for, and nothing at all otherwise.
    fileprivate struct DynamicTypeSizeOverride: ViewModifier {
        func body(content: Content) -> some View {
            if let size = UITestBootstrap.requestedDynamicTypeSize {
                content.dynamicTypeSize(size)
            } else {
                content
            }
        }
    }

    /// The type size a UI test asked for, or nil to leave the system's alone.
    static var requestedDynamicTypeSize: DynamicTypeSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting") else { return nil }
        if arguments.contains("--dynamic-type-accessibility-xxxlarge") { return .accessibility5 }
        if arguments.contains("--dynamic-type-xxxlarge") { return .xxxLarge }
        if arguments.contains("--dynamic-type-small") { return .small }
        if arguments.contains("--dynamic-type-large") { return .large }
        return nil
    }

    static func prepareIfRequested(container: ModelContainer) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting") else { return }

        let context = container.mainContext
        if arguments.contains("--reset-state") {
            // Deleting the children first threw "Batch delete failed due to mandatory OTO
            // nullify inverse on ChapterModel/audiobook", and that throw surfaced as the
            // "Library unavailable" screen — every UI test then failed at launch. Books are
            // the only root: chapters, bookmarks and transcripts cascade from them.
            for book in try context.fetch(FetchDescriptor<AudiobookModel>()) {
                context.delete(book)
            }
            try context.save()
        }

        if arguments.contains("--seed-showcase") {
            try seedShowcase(context: context)
            return
        }

        // A linked series, for the suites and screenshots that need the library grouped.
        // Seeded once: without `--reset-state` this runs again on every launch, and the shelf
        // would grow a second Mistborn every time.
        let seriesAlreadySeeded = try context
            .fetch(FetchDescriptor<AudiobookModel>())
            .contains { $0.hardcover?.seriesName == "Mistborn" }
        if arguments.contains("--seed-series"), !seriesAlreadySeeded {
            let audioURL = try createSilentWaveFile()
            let volumes = [
                ("The Final Empire", 1.0, 0.12),
                ("The Well of Ascension", 2.0, 0.0),
                ("The Hero of Ages", 3.0, 0.0)
            ]
            for (title, position, progress) in volumes {
                let volume = AudiobookModel(
                    title: title,
                    author: "Brandon Sanderson",
                    fileURL: AudiobookModel.storedPath(for: audioURL),
                    duration: 30,
                    currentPosition: 30 * progress,
                    dateAdded: Date(),
                    lastPlayed: .distantPast
                )
                volume.hardcover = HardcoverLink(
                    id: Int(position),
                    title: title,
                    author: "Brandon Sanderson",
                    seriesID: 42,
                    seriesName: "Mistborn",
                    seriesPosition: position,
                    seriesChecked: true,
                    summary: """
                        For a thousand years the ash fell and no flowers bloomed. For a thousand \
                        years the Lord Ruler reigned, and the skaa served. Then a thief \
                        discovered Allomancy — and set out to overthrow a god.
                        """,
                    genres: ["Fantasy", "Epic Fantasy"],
                    moods: ["Adventurous", "Dark"],
                    contentWarnings: ["Violence"],
                    detailsChecked: true
                )
                context.insert(volume)
            }
            // A catalogue one volume longer than the shelf, so the card has something to
            // report as missing.
            SeriesCatalog.store(
                [
                    SeriesVolume(bookID: 1, title: "The Final Empire", position: 1),
                    SeriesVolume(bookID: 2, title: "The Well of Ascension", position: 2),
                    SeriesVolume(bookID: 3, title: "The Hero of Ages", position: 3),
                    SeriesVolume(bookID: 4, title: "The Alloy of Law", position: 4)
                ],
                for: 42
            )
            try context.save()
        }

        // A book left by an earlier run can point into that run's app container, which resolves
        // to nothing today. Playback then fails silently, and so does every test that needs
        // audio, so keep the existing fixture only while its audio is actually there.
        if let existing = try context.fetch(FetchDescriptor<AudiobookModel>()).first {
            if let url = existing.resolvedFileURL, FileManager.default.fileExists(atPath: url.path) {
                return
            }
            for book in try context.fetch(FetchDescriptor<AudiobookModel>()) {
                context.delete(book)
            }
            try context.save()
        }

        let audioURL = try createSilentWaveFile()
        let book = AudiobookModel(
            title: "UI Test Audiobook",
            author: "UI Test Author",
            // Relative to the library folder, like an imported book, so it survives the
            // container UUID changing between installs.
            fileURL: AudiobookModel.storedPath(for: audioURL),
            duration: 30,
            currentPosition: 0,
            isFinished: false,
            dateAdded: Date(),
            lastPlayed: .distantPast
        )
        let chapter = ChapterModel(
            title: "Chapter 1",
            chapterNumber: 1,
            startTime: 0,
            endTime: 30
        )
        chapter.audiobook = book
        context.insert(book)
        context.insert(chapter)
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: audioURL)
            throw error
        }
    }

    private static func createSilentWaveFile() throws -> URL {
        let fileManager = FileManager.default
        // The library folder, where imported audio lives: a path under it is stored relative.
        let directory = AudiobookModel.libraryFolderURL.appendingPathComponent("UITestFixtures", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("silent.wav")
        if fileManager.fileExists(atPath: url.path) { return url }
        try writeSilentWave(to: url, seconds: 30)
        return url
    }

    /// A real, playable WAV of a known length. Tests that have to measure a file need one.
    static func writeSilentWave(to url: URL, seconds: UInt32) throws {
        let sampleRate: UInt32 = 8_000
        let sampleCount = sampleRate * seconds
        let dataSize = sampleCount * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(36 + dataSize, to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * 2, to: &data)
        appendLittleEndian(UInt16(2), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(count: Int(dataSize)))
        try data.write(to: url, options: .atomic)
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

extension View {
    /// Honours the UI suites' `--dynamic-type-*` arguments, which nothing used to read — so
    /// every dynamic type test asserted against the default size.
    func uiTestDynamicTypeSize() -> some View {
        modifier(UITestBootstrap.DynamicTypeSizeOverride())
    }
}
#endif
