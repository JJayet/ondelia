import Foundation
import Testing
@testable import IsoraWatch_Watch_App

/// The two rules the watch cannot get wrong: the manifest must describe the *whole* book even
/// when most of it is still on the phone, and a stale progress write must never win.
struct WatchLibraryDiskTests {
    private func entries(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["chapters"] as? [[String: Any]] ?? []
    }

    @Test func manifestListsEveryChapterIncludingTheOnesNotOnDisk() throws {
        let chapters = [
            ChapterSummary(number: 2, title: "Two", start: 100, end: 250),
            ChapterSummary(number: 1, title: "One", start: 0, end: 100),
            ChapterSummary(number: 3, title: nil, start: 250, end: 300)
        ]
        let rows = try entries(from: try WatchLibraryDisk.manifestData(chapters: chapters))

        #expect(rows.count == 3)
        #expect(rows.map { $0["chapterNumber"] as? Int } == [1, 2, 3])
        #expect(rows.map { $0["fileName"] as? String } == ["chapter-1.m4a", "chapter-2.m4a", "chapter-3.m4a"])
        #expect(rows.map { $0["duration"] as? Double } == [100, 150, 50])
    }

    @Test func manifestKeepsGapsSoLaterChaptersStartInTheRightPlace() throws {
        let chapters = (1...4).map { ChapterSummary(number: $0, start: Double($0 - 1) * 60, end: Double($0) * 60) }
        let rows = try entries(from: try WatchLibraryDisk.manifestData(chapters: chapters))
        // Nothing is on disk in this test, yet every chapter is listed with its real duration,
        // which is what makes the summed timeline match the book.
        #expect(rows.compactMap { $0["duration"] as? Double }.reduce(0, +) == 240)
        #expect(rows.compactMap { $0["startTime"] as? Double } == [0, 60, 120, 180])
    }

    @Test func chapterNumberRoundTripsThroughTheFileName() {
        #expect(WatchLibraryDisk.chapterNumber(fromFileName: WatchLibraryDisk.chapterFileName(14)) == 14)
        #expect(WatchLibraryDisk.chapterNumber(fromFileName: "audiobook_manifest.json") == nil)
        #expect(WatchLibraryDisk.chapterNumber(fromFileName: "chapter-x.m4a") == nil)
        // The book folder also holds the cover, which is not audio and must not be counted.
        #expect(WatchLibraryDisk.chapterNumber(fromFileName: "cover.jpg") == nil)
    }

    @Test func lastWriteWins() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)

        #expect(WatchLibraryDisk.shouldApplyRemotePosition(remote: new, local: old))
        #expect(!WatchLibraryDisk.shouldApplyRemotePosition(remote: old, local: new))
        #expect(!WatchLibraryDisk.shouldApplyRemotePosition(remote: old, local: old))
        // A local row with no timestamp predates everything, so any dated remote write lands.
        #expect(WatchLibraryDisk.shouldApplyRemotePosition(remote: old, local: nil))
        // A remote write with no timestamp cannot be compared, so it never wins.
        #expect(!WatchLibraryDisk.shouldApplyRemotePosition(remote: nil, local: nil))
        #expect(!WatchLibraryDisk.shouldApplyRemotePosition(remote: nil, local: old))
    }
}
