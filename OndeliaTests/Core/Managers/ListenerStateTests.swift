import Testing
import Foundation
import SwiftData
@testable import Isora

@MainActor
struct ListenerStateTests {
    let controller = SwiftDataController.inMemory()
    let statistics: ReadingStatistics
    let now = Date(timeIntervalSince1970: 1_000_000)
    /// What each adapter heard, keyed by the source it speaks for ("none" for Hardcover-like ones).
    final class Heard { var log: [String: [ListenerState.Accepted]] = [:] }
    let heard = Heard()
    let state: ListenerState

    init() {
        statistics = ReadingStatistics(store: controller)
        let heard = heard
        func recorder(_ source: ListenerState.Source?) -> ListenerState.Outbound {
            .init(source: source) { heard.log["\(source.map { "\($0)" } ?? "none")", default: []].append($0) }
        }
        let now = now
        state = ListenerState(
            store: controller,
            statistics: statistics,
            outbound: [recorder(.player), recorder(.server), recorder(.watch), recorder(nil)],
            clock: { now }
        )
    }

    private func book(duration: TimeInterval = 3600) -> AudiobookModel {
        let book = AudiobookModel(title: "Dune", duration: duration)
        controller.context.insert(book)
        return book
    }

    private var finishCount: Int { statistics.sessions.filter(\.finishedBook).count }

    @Test("A change reaches every adapter except the one for its own source")
    func fanOutSkipsSource() {
        let book = book()
        state.apply(.position(10), to: book, from: .player)
        state.apply(.position(20), to: book, from: .watch, at: now.addingTimeInterval(10))
        state.apply(.position(30), to: book, from: .server, at: now.addingTimeInterval(20))
        state.apply(.reset, to: book, from: .listener)

        #expect(heard.log["player"]?.map(\.source) == [.watch, .server, .listener])
        #expect(heard.log["watch"]?.map(\.source) == [.player, .server, .listener])
        #expect(heard.log["server"]?.map(\.source) == [.player, .watch, .listener])
        #expect(heard.log["none"]?.map(\.source) == [.player, .watch, .server, .listener])
    }

    @Test("A local position is stamped now, saved, and moves lastPlayed")
    func localPosition() {
        let book = book()
        state.apply(.position(1200), to: book, from: .player)
        #expect(book.currentPosition == 1200)
        #expect(book.positionUpdatedAt == now)
        #expect(book.lastPlayed == now)
        #expect(book.isFinished == false)
        #expect(controller.context.hasChanges == false)
    }

    @Test("A remote position wins only when more than a second newer, and is never told back")
    func remoteLastWriteWins() {
        let book = book()
        state.apply(.position(100), to: book, from: .player)

        #expect(!state.apply(.position(50), to: book, from: .watch, at: now.addingTimeInterval(-60)))
        #expect(!state.apply(.position(50), to: book, from: .server, at: now.addingTimeInterval(0.5)))
        #expect(book.currentPosition == 100)
        #expect(heard.log["none"]?.count == 1)

        #expect(state.apply(.position(50), to: book, from: .server, at: now.addingTimeInterval(5)))
        #expect(book.currentPosition == 50)
        #expect(book.positionUpdatedAt == now.addingTimeInterval(5))
    }

    @Test("A position written before position sync loses to any remote one")
    func unstampedLocalLoses() {
        let book = book()
        #expect(book.positionUpdatedAt == nil)
        #expect(state.apply(.position(5), to: book, from: .watch, at: .distantPast.addingTimeInterval(1)))
    }

    @Test("A remote listen never moves lastPlayed back")
    func remoteKeepsLaterLastPlayed() {
        let book = book()
        book.lastPlayed = now.addingTimeInterval(100)
        state.apply(.position(5), to: book, from: .server, at: now)
        #expect(book.lastPlayed == now.addingTimeInterval(100))
    }

    @Test("Within 30 s of the end is one Finish, however many ticks land there")
    func nearEndFinishesOnce() {
        let book = book(duration: 3600)
        state.apply(.position(3569), to: book, from: .player)
        #expect(book.isFinished == false)
        state.apply(.position(3570), to: book, from: .player)
        state.apply(.position(3580), to: book, from: .player)
        #expect(book.isFinished == true)
        #expect(finishCount == 1)
        #expect(heard.log["none"]?.map(\.finishedChanged) == [false, true, false])
    }

    @Test("The server's position near the end is not a Finish; its own flag is")
    func serverNearEndIsNotFinish() {
        let book = book(duration: 3600)
        state.apply(.position(3590), to: book, from: .server, at: now)
        #expect(book.isFinished == false)
        #expect(finishCount == 0)
    }

    @Test("A watch position at the end is a Finish")
    func watchNearEndFinishes() {
        let book = book(duration: 3600)
        state.apply(.position(3590), to: book, from: .watch, at: now)
        #expect(book.isFinished == true)
        #expect(finishCount == 1)
    }

    @Test("Marked finished by hand moves the position to the end; the end of playback does not")
    func finishPosition() {
        let byHand = book(duration: 3600)
        state.apply(.position(500), to: byHand, from: .player)
        state.apply(.finish, to: byHand, from: .listener)
        #expect(byHand.isFinished == true)
        #expect(byHand.currentPosition == 3600)

        let ended = book(duration: 3600)
        state.apply(.position(3500), to: ended, from: .player)
        state.apply(.finish, to: ended, from: .player)
        #expect(ended.currentPosition == 3500)
        #expect(finishCount == 2)
    }

    @Test("A server Finish next to one already logged is not logged again")
    func serverFinishDeduplicated() {
        let book = book()
        state.apply(.finish, to: book, from: .listener)
        state.apply(.unfinish, to: book, from: .listener)
        state.apply(.finish, to: book, from: .server, at: now.addingTimeInterval(3600))
        #expect(book.isFinished == true)
        #expect(finishCount == 1)

        state.apply(.unfinish, to: book, from: .listener)
        state.apply(.finish, to: book, from: .server, at: now.addingTimeInterval(3 * 86_400))
        #expect(finishCount == 2)
    }

    @Test("Reset goes back to the start and leaves Finished alone")
    func resetKeepsFinished() {
        let book = book()
        state.apply(.finish, to: book, from: .listener)
        state.apply(.reset, to: book, from: .listener)
        #expect(book.currentPosition == 0)
        #expect(book.positionUpdatedAt == now)
        #expect(book.isFinished == true)
        #expect(controller.context.hasChanges == false)
    }

    @Test("Unfinish clears Finished and reports the flip")
    func unfinish() {
        let book = book()
        state.apply(.finish, to: book, from: .listener)
        state.apply(.unfinish, to: book, from: .listener)
        #expect(book.isFinished == false)
        #expect(heard.log["none"]?.map(\.finishedChanged) == [true, true])
    }
}
