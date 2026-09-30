//
//  ZIPImporterValidationTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("ZIP content validation")
struct ZIPImporterValidationTests {
    private func folder(_ files: [String: Int]) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, size) in files {
            try Data(count: size).write(to: folder.appending(path: name))
        }
        return folder
    }

    @Test("A short book is accepted: one small m4b next to its cover")
    func smallBook() throws {
        let book = try folder(["Edgar.m4b": 200_000, "Edgar.jpg": 50_000])
        defer { try? FileManager.default.removeItem(at: book) }
        #expect(ZIPImporter.validateAudiobookContent(in: book) == book)
    }

    @Test("An archive with no audio, or only empty audio, is refused")
    func noAudio() throws {
        let cover = try folder(["cover.jpg": 50_000])
        let empty = try folder(["01.mp3": 0])
        defer { for url in [cover, empty] { try? FileManager.default.removeItem(at: url) } }
        #expect(ZIPImporter.validateAudiobookContent(in: cover) == nil)
        #expect(ZIPImporter.validateAudiobookContent(in: empty) == nil)
    }
}
