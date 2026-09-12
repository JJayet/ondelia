import Foundation
import Testing
@testable import Isora

@MainActor
struct TranscriptionRequestTests {
    private let url = URL(fileURLWithPath: "/tmp/book.m4b")
    private let bookID = UUID()

    private func make(chapters: [ChapterModel] = [], tracks: [AudiobookTrack], time: TimeInterval) -> TranscriptionRequest? {
        TranscriptionRequest.make(audiobookID: bookID, chapters: chapters, tracks: tracks, time: time)
    }

    @Test("A short track is one window")
    func shortTrackIsWhole() {
        let tracks = [AudiobookTrack(url: url, start: 0, duration: 300), AudiobookTrack(url: url, start: 300, duration: 400)]
        let request = make(tracks: tracks, time: 350)

        #expect(request?.trackIndex == 1)
        #expect(request?.start == 0)
        #expect(request?.end == 400)
        #expect(request?.trackStart == 300)
        #expect(request?.contains(bookTime: 699) == true)
        #expect(request?.contains(bookTime: 700) == false)
    }

    @Test("A long single file uses its embedded chapter when that fits a window")
    func singleFileUsesChapter() {
        let chapter = ChapterModel(title: "Two", startTime: 500, endTime: 900)
        let request = make(chapters: [chapter], tracks: [AudiobookTrack(url: url, start: 0, duration: 36_000)], time: 700)

        #expect(request?.start == 500)
        #expect(request?.end == 900)
        #expect(request?.title == "Two")
    }

    @Test("A long chapter falls back to fixed windows aligned to the track")
    func longChapterIsBucketed() {
        let chapter = ChapterModel(title: "Long", startTime: 0, endTime: 36_000)
        let request = make(chapters: [chapter], tracks: [AudiobookTrack(url: url, start: 0, duration: 36_000)], time: 1_450)

        #expect(request?.start == 1_200)
        #expect(request?.end == 1_800)
        #expect(request?.title == nil)
    }

    @Test("A folder book ignores chapter rows and windows within the file")
    func folderBookIgnoresChapters() {
        let chapter = ChapterModel(title: "One", startTime: 0, endTime: 100)
        let tracks = [AudiobookTrack(url: url, start: 0, duration: 3_000), AudiobookTrack(url: url, start: 3_000, duration: 3_000)]
        let request = make(chapters: [chapter], tracks: tracks, time: 3_650)

        #expect(request?.trackIndex == 1)
        #expect(request?.start == 600)
        #expect(request?.end == 1_200)
        #expect(request?.bookRange == 3_600..<4_200)
    }

    @Test("The last window stops at the end of the track")
    func lastWindowIsClipped() {
        let request = make(tracks: [AudiobookTrack(url: url, start: 0, duration: 1_500)], time: 1_499)

        #expect(request?.start == 1_200)
        #expect(request?.end == 1_500)
    }

    @Test("No tracks, no request")
    func noTracks() {
        #expect(make(tracks: [], time: 0) == nil)
    }
}
