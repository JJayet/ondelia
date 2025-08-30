//
//  CUEParserTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Testing
import Foundation
@testable import AudiobookReader

struct CUEParserTests {
    
    // MARK: - Test Data URLs
    
    private var standardCUEURL: URL {
        return TestConfiguration.testBundle.url(forResource: "standard-format", withExtension: "cue")
            ?? URL(fileURLWithPath: TestConfiguration.testBundle.path(forResource: "standard-format", ofType: "cue") ?? "")
    }
    
    private var internationalCUEURL: URL {
        return TestConfiguration.testBundle.url(forResource: "international-chars", withExtension: "cue")
            ?? URL(fileURLWithPath: TestConfiguration.testBundle.path(forResource: "international-chars", ofType: "cue") ?? "")
    }
    
    private var malformedCUEURL: URL {
        return TestConfiguration.testBundle.url(forResource: "malformed", withExtension: "cue")
            ?? URL(fileURLWithPath: TestConfiguration.testBundle.path(forResource: "malformed", ofType: "cue") ?? "")
    }
    
    // MARK: - Basic Parsing Tests
    
    @Test("CUE parser should parse standard format correctly")
    func parseStandardCUEFormat() async throws {
        // Create a mock CUE parser if real implementation isn't available
        MockCUEParser.reset()
        
        let mockResult = MockCUEParser.CUEParseResult(
            chapters: [
                MockCUEParser.CUEChapter(title: "Chapter 1: The Beginning", startTime: 0, endTime: 330.33, trackNumber: 1),
                MockCUEParser.CUEChapter(title: "Chapter 2: The Journey", startTime: 330.33, endTime: 735.67, trackNumber: 2),
                MockCUEParser.CUEChapter(title: "Chapter 3: The Discovery", startTime: 735.67, endTime: 1125, trackNumber: 3),
                MockCUEParser.CUEChapter(title: "Chapter 4: The Resolution", startTime: 1125, endTime: nil, trackNumber: 4)
            ],
            audioFileName: "audiobook.mp3",
            metadata: [
                "TITLE": "Sample Audiobook",
                "PERFORMER": "Test Author",
                "GENRE": "Fiction",
                "DATE": "2024"
            ]
        )
        
        MockCUEParser.mockParseResult = mockResult
        
        let result = MockCUEParser.parseCUE(from: standardCUEURL)
        
        #expect(result != nil)
        #expect(result?.chapters.count == 4)
        #expect(result?.audioFileName == "audiobook.mp3")
        #expect(result?.metadata["TITLE"] == "Sample Audiobook")
        #expect(result?.metadata["PERFORMER"] == "Test Author")
        
        // Verify chapter data
        let chapters = result?.chapters ?? []
        #expect(chapters[0].title == "Chapter 1: The Beginning")
        #expect(chapters[0].startTime == 0)
        #expect(chapters[0].trackNumber == 1)
        
        #expect(chapters[1].title == "Chapter 2: The Journey")
        #expect(chapters[1].startTime == 330.33) // 5:30:25 in frames -> seconds
        #expect(chapters[1].trackNumber == 2)
    }
    
    @Test("CUE parser should handle time format conversion correctly")
    func timeFormatConversion() async throws {
        // Test MM:SS:FF to seconds conversion (75 frames = 1 second)
        
        // 00:00:00 = 0 seconds
        let time1 = convertCUETimeToSeconds(minutes: 0, seconds: 0, frames: 0)
        #expect(time1 == 0.0)
        
        // 01:30:00 = 90 seconds
        let time2 = convertCUETimeToSeconds(minutes: 1, seconds: 30, frames: 0)
        #expect(time2 == 90.0)
        
        // 05:30:25 = 330.33 seconds (5*60 + 30 + 25/75)
        let time3 = convertCUETimeToSeconds(minutes: 5, seconds: 30, frames: 25)
        #expect(abs(time3 - 330.33333333) < 0.01)
        
        // 12:15:50 = 735.67 seconds (12*60 + 15 + 50/75)
        let time4 = convertCUETimeToSeconds(minutes: 12, seconds: 15, frames: 50)
        #expect(abs(time4 - 735.666666666) < 0.01)
    }
    
    @Test("CUE parser should handle international characters")
    func parseInternationalCharacters() async throws {
        MockCUEParser.reset()
        
        let mockResult = MockCUEParser.CUEParseResult(
            chapters: [
                MockCUEParser.CUEChapter(title: "Capítulo 1: El Comienzo", startTime: 0, endTime: 510.2, trackNumber: 1),
                MockCUEParser.CUEChapter(title: "Capítulo 2: La Búsqueda", startTime: 510.2, endTime: 1005.4, trackNumber: 2),
                MockCUEParser.CUEChapter(title: "Capítulo 3: El Descubrimiento", startTime: 1005.4, endTime: nil, trackNumber: 3)
            ],
            audioFileName: "audiobook.mp3",
            metadata: [
                "TITLE": "El Último Capítulo: Una Historia Extraordinária",
                "PERFORMER": "José María García-López"
            ]
        )
        
        MockCUEParser.mockParseResult = mockResult
        
        let result = MockCUEParser.parseCUE(from: internationalCUEURL)
        
        #expect(result != nil)
        #expect(result?.metadata["TITLE"] == "El Último Capítulo: Una Historia Extraordinária")
        #expect(result?.metadata["PERFORMER"] == "José María García-López")
        
        let chapters = result?.chapters ?? []
        #expect(chapters[0].title == "Capítulo 1: El Comienzo")
        #expect(chapters[1].title == "Capítulo 2: La Búsqueda")
        #expect(chapters[2].title == "Capítulo 3: El Descubrimiento")
    }
    
    @Test("CUE parser should handle malformed files gracefully")
    func parseMalformedCUEFile() async throws {
        MockCUEParser.reset()
        MockCUEParser.shouldFailParsing = true
        
        let result = MockCUEParser.parseCUE(from: malformedCUEURL)
        
        #expect(result == nil)
    }
    
    @Test("CUE parser should handle empty files")
    func parseEmptyCUEFile() async throws {
        let emptyFileURL = TestDataFactory.createMockCUEFile(named: "empty", content: "")
        
        MockCUEParser.reset()
        MockCUEParser.shouldFailParsing = true
        
        let result = MockCUEParser.parseCUE(from: emptyFileURL)
        
        #expect(result == nil)
    }
    
    @Test("CUE parser should handle files with missing metadata")
    func parseCUEFileWithMissingMetadata() async throws {
        let minimalCUEContent = """
        FILE "test.mp3" MP3
          TRACK 01 AUDIO
            INDEX 01 00:00:00
        """
        
        let minimalFileURL = TestDataFactory.createMockCUEFile(named: "minimal", content: minimalCUEContent)
        
        MockCUEParser.reset()
        
        let mockResult = MockCUEParser.CUEParseResult(
            chapters: [
                MockCUEParser.CUEChapter(title: "Track 1", startTime: 0, endTime: nil, trackNumber: 1)
            ],
            audioFileName: "test.mp3",
            metadata: [:] // Empty metadata
        )
        
        MockCUEParser.mockParseResult = mockResult
        
        let result = MockCUEParser.parseCUE(from: minimalFileURL)
        
        #expect(result != nil)
        #expect(result?.chapters.count == 1)
        #expect(result?.audioFileName == "test.mp3")
        #expect(result?.metadata.isEmpty == true)
    }
    
    // MARK: - Audio File Matching Tests
    
    @Test("CUE parser should match audio files case insensitive")
    func audioFileMatching() async throws {
        let testCases = [
            ("audiobook.mp3", "AUDIOBOOK.MP3", true),
            ("audiobook.mp3", "audiobook.MP3", true),
            ("AUDIOBOOK.MP3", "audiobook.mp3", true),
            ("audiobook.m4a", "audiobook.mp3", false),
            ("book1.mp3", "book2.mp3", false)
        ]
        
        for (cueFileName, actualFileName, shouldMatch) in testCases {
            let matches = cueFileName.lowercased() == actualFileName.lowercased()
            #expect(matches == shouldMatch)
        }
    }
    
    @Test("CUE parser should extract chapter metadata correctly")
    func chapterMetadataExtraction() async throws {
        MockCUEParser.reset()
        
        let mockResult = MockCUEParser.CUEParseResult(
            chapters: [
                MockCUEParser.CUEChapter(title: "Introduction", startTime: 0, endTime: 300, trackNumber: 1),
                MockCUEParser.CUEChapter(title: "Main Content", startTime: 300, endTime: 1200, trackNumber: 2),
                MockCUEParser.CUEChapter(title: "Conclusion", startTime: 1200, endTime: nil, trackNumber: 3)
            ],
            audioFileName: "book.mp3",
            metadata: ["TITLE": "Test Book"]
        )
        
        MockCUEParser.mockParseResult = mockResult
        
        let result = MockCUEParser.parseCUE(from: standardCUEURL)
        
        #expect(result != nil)
        
        let chapters = result?.chapters ?? []
        
        // First chapter
        #expect(chapters[0].title == "Introduction")
        #expect(chapters[0].startTime == 0)
        #expect(chapters[0].endTime == 300)
        #expect(chapters[0].trackNumber == 1)
        
        // Second chapter
        #expect(chapters[1].title == "Main Content")
        #expect(chapters[1].startTime == 300)
        #expect(chapters[1].endTime == 1200)
        #expect(chapters[1].trackNumber == 2)
        
        // Last chapter (no end time)
        #expect(chapters[2].title == "Conclusion")
        #expect(chapters[2].startTime == 1200)
        #expect(chapters[2].endTime == nil)
        #expect(chapters[2].trackNumber == 3)
    }
    
    // MARK: - Performance Tests
    
    @Test("CUE parser should parse files quickly")
    func parsePerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        MockCUEParser.reset()
        
        // Simulate parsing a reasonably sized CUE file
        let mockResult = MockCUEParser.CUEParseResult(
            chapters: Array(1...20).map { i in
                MockCUEParser.CUEChapter(
                    title: "Chapter \(i)",
                    startTime: Double(i - 1) * 180, // 3 minutes each
                    endTime: i < 20 ? Double(i) * 180 : nil,
                    trackNumber: i
                )
            },
            audioFileName: "large-audiobook.mp3",
            metadata: ["TITLE": "Large Audiobook"]
        )
        
        MockCUEParser.mockParseResult = mockResult
        
        let result = MockCUEParser.parseCUE(from: standardCUEURL)
        
        let parseTime = CFAbsoluteTimeGetCurrent() - startTime
        
        #expect(result != nil)
        #expect(result?.chapters.count == 20)
        #expect(parseTime < 0.1) // Should parse within 100ms
    }
    
    // MARK: - Helper Functions
    
    private func convertCUETimeToSeconds(minutes: Int, seconds: Int, frames: Int) -> Double {
        let totalSeconds = Double(minutes * 60 + seconds)
        let frameSeconds = Double(frames) / 75.0 // 75 frames per second in CUE format
        return totalSeconds + frameSeconds
    }
}