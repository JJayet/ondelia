//
//  ZIPImporterValidationTests.swift
//  IsoraTests
//

import Testing
import Foundation
import ZIPFoundation
@testable import Isora

@Suite("ZIP content validation")
struct ZIPImporterValidationTests {
    private func folder(_ files: [String: Int]) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, size) in files {
            let file = folder.appending(path: name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: size).write(to: file)
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

    @Test("Sibling disc folders are all kept, from the folder that wraps them")
    func multiDisc() throws {
        let root = try folder(["Book/Disc 1/01.mp3": 1_000, "Book/Disc 2/01.mp3": 1_000, "Book/cover.jpg": 10])
        defer { try? FileManager.default.removeItem(at: root) }
        let book = root.appending(path: "Book")
        #expect(ZIPImporter.validateAudiobookContent(in: root)?.standardizedFileURL.path == book.standardizedFileURL.path)
    }
}

@Suite("ZIP extraction limits")
struct ZIPImporterExtractionTests {
    /// One deflated `book.mp3`; `declaredSize` overwrites its uncompressed size in both headers.
    private func archive(declaredSize: UInt32? = nil) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
        // Random bytes, so the compression ratio stays plausible while the declared size lies.
        let payload = Data((0..<65_536).map { _ in UInt8.random(in: 0...255) })
        do {
            let archive = try Archive(url: url, accessMode: .create)
            try archive.addEntry(
                with: "book.mp3",
                type: .file,
                uncompressedSize: Int64(payload.count),
                compressionMethod: .deflate
            ) { position, size in
                payload.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        guard let declaredSize else { return url }
        var bytes = try Data(contentsOf: url)
        // The local file header keeps the uncompressed size at offset 22, the central directory at 24.
        let headers: [([UInt8], Int)] = [([0x50, 0x4B, 0x03, 0x04], 22), ([0x50, 0x4B, 0x01, 0x02], 24)]
        for (signature, offset) in headers {
            let start = try #require(bytes.firstRange(of: Data(signature))).lowerBound + offset
            withUnsafeBytes(of: declaredSize.littleEndian) { bytes.replaceSubrange(start..<start + 4, with: $0) }
        }
        try bytes.write(to: url)
        return url
    }

    @Test("An honest archive extracts in full")
    func honestArchive() throws {
        let zip = try archive()
        defer { try? FileManager.default.removeItem(at: zip) }
        let extracted = try #require(ZIPImporter.importZIPFile(from: zip))
        defer { ZIPImporter.cleanupDirectory(at: extracted.root) }
        let book = extracted.folder.appending(path: "book.mp3")
        #expect(try FileManager.default.attributesOfItem(atPath: book.path)[.size] as? Int == 65_536)
    }

    @Test("An entry inflating past its declared size is refused")
    func lyingArchive() throws {
        let zip = try archive(declaredSize: 1_024)
        defer { try? FileManager.default.removeItem(at: zip) }
        #expect(ZIPImporter.importZIPFile(from: zip) == nil)
    }
}
