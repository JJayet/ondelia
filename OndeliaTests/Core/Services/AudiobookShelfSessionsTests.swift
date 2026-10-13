//
//  AudiobookShelfSessionsTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("AudiobookShelf listening sessions")
@MainActor
struct AudiobookShelfSessionsTests {
    private func session(startedAt: Date = Date(), seconds: Double) -> ListeningSessionModel {
        ListeningSessionModel(book: AudiobookModel(title: "Dune", author: "Frank Herbert"), startedAt: startedAt, seconds: seconds)
    }

    @Test("A session is dated on the listener's day, not the server's")
    func payload() throws {
        // 23:30 in Paris on Tuesday 13 October 2026, already Wednesday in UTC+3.
        let start = Date(timeIntervalSince1970: 1_791_927_000)
        let listened = session(startedAt: start, seconds: 600)
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        let local = AudiobookShelfAPI.LocalSession(listened, item: "li_a", position: 120, duration: 3600, timeZone: paris)
        #expect(local.date == "2026-10-13")
        #expect(local.dayOfWeek == "Tuesday")
        #expect(local.id == listened.id.uuidString.lowercased())
        #expect(local.timeListening == 600)
        #expect(local.currentTime == 120)
        #expect(local.updatedAt - local.startedAt == 600_000)
        let moscow = try #require(TimeZone(identifier: "Europe/Moscow"))
        let east = AudiobookShelfAPI.LocalSession(listened, item: "li_a", position: 120, duration: 3600, timeZone: moscow)
        #expect(east.date == "2026-10-14")
        #expect(east.dayOfWeek == "Wednesday")
    }

    @Test("Only new sessions, or ones that grew a second or more, are sent")
    func unsent() {
        let new = session(seconds: 30)
        let grown = session(seconds: 95)
        let same = session(seconds: 60.4)
        let marker = session(seconds: 0)
        let sent = [
            grown.id.uuidString.lowercased(): 60.0,
            same.id.uuidString.lowercased(): 60.0
        ]
        let pending = AudiobookShelfService.unsent([new, grown, same, marker], sent: sent)
        #expect(pending.map(\.id) == [new.id, grown.id])
    }
}
