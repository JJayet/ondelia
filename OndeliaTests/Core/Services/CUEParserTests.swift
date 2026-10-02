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
}
