//
//  AudiobookShelfStreamingTests.swift
//  IsoraTests
//

import Testing
import Foundation
import SwiftData
@testable import Isora

@Suite("AudiobookShelf streaming and progress")
@MainActor
struct AudiobookShelfStreamingTests {
    typealias Pushed = AudiobookShelfService.PushedProgress

    @Test("Progress is pushed on the first write, every 30 s while playing, and on the last word")
    func pushThrottle() {
        let push = AudiobookShelfService.shouldPush
        #expect(push(Pushed(position: 10, isFinished: false), nil, true))
        #expect(!push(Pushed(position: 20, isFinished: false), Pushed(position: 10, isFinished: false), true))
        #expect(push(Pushed(position: 41, isFinished: false), Pushed(position: 10, isFinished: false), true))
        // Paused: whatever moved is the last word, so it goes.
        #expect(push(Pushed(position: 12, isFinished: false), Pushed(position: 10, isFinished: false), false))
        // Nothing moved: nothing to say.
        #expect(!push(Pushed(position: 10.4, isFinished: false), Pushed(position: 10, isFinished: false), false))
        // Marked unread at the same position still counts.
        #expect(push(Pushed(position: 10, isFinished: false), Pushed(position: 10, isFinished: true), false))
    }

    @Test("The server position wins only when newer, with a second of slack")
    func serverIsNewer() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func remote(_ seconds: Double) throws -> AudiobookShelfAPI.MediaProgress {
            let json = #"{"currentTime":42,"isFinished":false,"lastUpdate":\#(seconds * 1000)}"#
            return try JSONDecoder().decode(AudiobookShelfAPI.MediaProgress.self, from: Data(json.utf8))
        }
        #expect(AudiobookShelfService.serverIsNewer(try remote(1_000_010), than: now))
        #expect(!AudiobookShelfService.serverIsNewer(try remote(1_000_000.5), than: now))
        #expect(!AudiobookShelfService.serverIsNewer(try remote(999_000), than: now))
        #expect(AudiobookShelfService.serverIsNewer(try remote(1), than: nil))
    }

    @Test("Stream addresses sit under the server's own path")
    func streamURL() throws {
        let server = try #require(URL(string: "https://host/abs"))
        let url = AudiobookShelfAPI.streamURL(server: server, contentPath: "/api/items/li_a/file/4395")
        #expect(url.absoluteString == "https://host/abs/api/items/li_a/file/4395")
    }

    @Test("An expanded item decodes into tracks, chapters and metadata")
    func playbackDecoding() throws {
        // Shape taken from AudiobookShelf 2.37.
        let json = """
        {"id":"li_a","media":{"duration":210,
          "tracks":[{"index":1,"startOffset":0,"duration":120,"contentUrl":"/api/items/li_a/file/1"},
                    {"index":2,"startOffset":120,"duration":90,"contentUrl":"/api/items/li_a/file/2"}],
          "chapters":[{"id":0,"start":0,"end":120,"title":"Part One"},{"id":1,"start":120,"end":210,"title":"Part Two"}],
          "metadata":{"title":"Dune","authors":[{"id":"x","name":"Frank Herbert"}],"narrators":[]}}}
        """
        let item = try JSONDecoder().decode(AudiobookShelfAPI.PlaybackItem.self, from: Data(json.utf8))
        #expect(item.media.tracks?.map(\.startOffset) == [0, 120])
        #expect(item.media.chapters?.map(\.title) == ["Part One", "Part Two"])
        #expect(item.author == "Frank Herbert")
        #expect(item.narrator == nil)
    }

    @Test("A downloaded file moves onto the streamed entry, which keeps its position and bookmarks")
    func adoptKeepsTheStreamedEntry() throws {
        // Held: the controller owns the container, and the context dies with it.
        let store = SwiftDataController.inMemory()
        let context = store.context
        let streamed = AudiobookModel(title: "Dune", fileURL: nil, duration: 200, currentPosition: 75)
        let imported = AudiobookModel(title: "Dune", fileURL: "Dune/", duration: 210)
        context.insert(streamed)
        context.insert(imported)
        let bookmark = BookmarkModel(title: "Spice", timestamp: 60, dateCreated: Date())
        context.insert(bookmark)
        bookmark.audiobook = streamed
        let chapter = ChapterModel(title: "Part One", chapterNumber: 1, startTime: 0, endTime: 120)
        context.insert(chapter)
        chapter.audiobook = imported
        context.insert(AudiobookShelfLinkModel(audiobookID: streamed.id, itemID: "li_a"))
        context.insert(AudiobookShelfLinkModel(audiobookID: imported.id, itemID: "li_a"))
        try context.save()

        AudiobookShelfService.adopt(imported, into: streamed, context: context)
        try context.save()

        let books = try context.fetch(FetchDescriptor<AudiobookModel>())
        #expect(books.map(\.id) == [streamed.id])
        #expect(streamed.fileURL == "Dune/")
        #expect(streamed.duration == 210)
        #expect(streamed.currentPosition == 75)
        #expect(streamed.bookmarks.map(\.title) == ["Spice"])
        #expect(streamed.chapters.map(\.title) == ["Part One"])
        let links = try context.fetch(FetchDescriptor<AudiobookShelfLinkModel>())
        #expect(links.map(\.audiobookID) == [streamed.id])
    }
}
