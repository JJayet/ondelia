#if DEBUG
import Foundation
import SwiftData

@MainActor
enum UITestBootstrap {
    static func prepareIfRequested(container: ModelContainer) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting") else { return }

        let context = container.mainContext
        if arguments.contains("--reset-state") {
            try context.delete(model: ChapterTranscriptionModel.self)
            try context.delete(model: BookmarkModel.self)
            try context.delete(model: ChapterModel.self)
            try context.delete(model: AudiobookModel.self)
            try context.save()
        }

        var descriptor = FetchDescriptor<AudiobookModel>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }

        let audioURL = try createSilentWaveFile()
        let book = AudiobookModel(
            title: "UI Test Audiobook",
            author: "UI Test Author",
            fileURL: audioURL.path,
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
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("UITestFixtures", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("silent.wav")
        if fileManager.fileExists(atPath: url.path) { return url }

        let sampleRate: UInt32 = 8_000
        let durationSeconds: UInt32 = 30
        let sampleCount = sampleRate * durationSeconds
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
        return url
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
#endif
