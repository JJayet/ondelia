import Testing
import Foundation
@testable import Isora

struct CUEParserTests {
    private func sample(_ name: String) throws -> URL {
        try #require(Bundle(for: TestBundleAnchor.self).url(forResource: name, withExtension: "cue"))
    }

    @Test("Parses standard CUE format")
    func parseStandardFormat() throws {
        let cue = try #require(CUEParser.parseCUEFile(at: try sample("standard-format")))
        #expect(cue.fileName == "audiobook.mp3")
        #expect(cue.fileType == "MP3")
        #expect(cue.title == "Sample Audiobook")
        #expect(cue.performer == "Test Author")
        #expect(cue.tracks.count == 4)
        #expect(cue.tracks[0].title == "Chapter 1: The Beginning")
        #expect(cue.tracks[0].startTime == 0)
        // 05:30:25 -> 5*60 + 30 + 25/75
        #expect(abs(cue.tracks[1].startTime - (330 + 25.0 / 75.0)) < 0.001)
        #expect(cue.tracks[3].number == 4)
    }

    @Test("Preserves international characters")
    func parseInternationalCharacters() throws {
        let cue = try #require(CUEParser.parseCUEFile(at: try sample("international-chars")))
        #expect(cue.performer == "José María García-López")
        #expect(cue.tracks.map(\.title) == ["Capítulo 1: El Comienzo", "Capítulo 2: La Búsqueda", "Capítulo 3: El Descubrimiento"])
    }

    @Test("Malformed CUE does not crash and keeps parseable tracks")
    func parseMalformed() throws {
        let cue = try #require(CUEParser.parseCUEFile(at: try sample("malformed")))
        #expect(cue.tracks.count == 3)
        #expect(cue.tracks[2].startTime == 0) // "invalid_time" falls back to 0
    }

    @Test("Missing file returns nil")
    func missingFile() {
        #expect(CUEParser.parseCUEFile(at: URL(fileURLWithPath: "/nonexistent/file.cue")) == nil)
    }

    @Test("An out-of-range time does not trap")
    func outOfRangeNumbers() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).cue")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        FILE "book.mp3" MP3
          TRACK 32768 AUDIO
            TITLE "Huge"
            INDEX 01 9223372036854775807:00:00
        """.write(to: url, atomically: true, encoding: .utf8)
        let cue = try #require(CUEParser.parseCUEFile(at: url))
        let track = try #require(cue.tracks.first)
        #expect(track.startTime.isFinite)
    }

    private func folder(_ files: [String: Data]) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        for (name, data) in files {
            let file = folder.appending(path: name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        return folder
    }

    private func sheet(_ file: String) -> Data {
        Data("FILE \"\(file)\" MP3\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n".utf8)
    }

    @Test("A Windows-1252 sheet keeps its accents")
    func parseWindows1252() throws {
        // "Capítulo" with í as the single Windows-1252 byte 0xED, which is not valid UTF-8.
        var bytes = Data("FILE \"book.mp3\" MP3\n  TRACK 01 AUDIO\n    TITLE \"Cap".utf8)
        bytes.append(0xED)
        bytes.append(Data("tulo\"\n    INDEX 01 00:00:00\n".utf8))
        let folder = try folder(["book.cue": bytes])
        defer { try? FileManager.default.removeItem(at: folder) }
        let cue = try #require(CUEParser.parseCUEFile(at: folder.appending(path: "book.cue")))
        #expect(cue.tracks.first?.title == "Capítulo")
    }

    @Test("A sheet naming several audio files is refused")
    func severalFilesRefused() throws {
        var bytes = sheet("part1.mp3")
        bytes.append(sheet("part2.mp3"))
        let folder = try folder(["book.cue": bytes])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(CUEParser.parseCUEFile(at: folder.appending(path: "book.cue")) == nil)
    }

    @Test("The audio file is found inside the folder only, with Windows separators")
    func containedAudioFile() throws {
        let parent = try folder(["outside.mp3": Data("x".utf8), "Book/Disc 1/01.mp3": Data("x".utf8)])
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = parent.appending(path: "Book")
        let escaping = CUEFile(fileName: "../outside.mp3", fileType: "MP3", tracks: [], title: nil, performer: nil)
        let windows = CUEFile(fileName: "Disc 1\\01.mp3", fileType: "MP3", tracks: [], title: nil, performer: nil)
        #expect(CUEParser.matchCUEWithAudioFile(cueFile: escaping, in: book) == nil)
        #expect(CUEParser.matchCUEWithAudioFile(cueFile: windows, in: book)?.lastPathComponent == "01.mp3")
    }

    @Test("Only a lone sheet naming one existing file makes a CUE book")
    func singleFileCUE() throws {
        let audio = Data("x".utf8)
        let single = try folder(["book.cue": sheet("book.mp3"), "book.mp3": audio])
        let two = try folder([
            "Part1.cue": sheet("Part1.mp3"), "Part1.mp3": audio,
            "Part2.cue": sheet("Part2.mp3"), "Part2.mp3": audio
        ])
        let missing = try folder(["book.cue": sheet("gone.wav"), "other.mp3": audio])
        defer { for url in [single, two, missing] { try? FileManager.default.removeItem(at: url) } }
        #expect(CUEParser.singleFileCUE(in: single)?.audioFile.lastPathComponent == "book.mp3")
        #expect(CUEParser.singleFileCUE(in: two) == nil)
        #expect(CUEParser.singleFileCUE(in: missing) == nil)
    }
}
