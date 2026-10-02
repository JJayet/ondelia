import Foundation
import Testing
@testable import Isora

@MainActor
@Suite("Series Collections made twice")
struct DuplicateCollectionsTests {
    @Test("Two copies of a series fold into the oldest, keeping both copies' books and chaining")
    func foldsIntoOldest() throws {
        UserDefaults.standard.removeObject(forKey: AudiobookManager.autoSeriesCollectionsKey)
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let context = manager.swiftDataController.context
        let one = AudiobookModel(title: "One")
        let two = AudiobookModel(title: "Two")
        context.insert(one)
        context.insert(two)
        // As iCloud would deliver them: another device's copy, made a moment later.
        let older = CollectionModel(name: "Mistborn", hardcoverSeriesID: 7, bookIDs: [one.id], dateCreated: Date(timeIntervalSince1970: 100))
        let newer = CollectionModel(name: "Mistborn", hardcoverSeriesID: 7, bookIDs: [two.id], dateCreated: Date(timeIntervalSince1970: 200))
        newer.autoContinue = true
        let server = AudiobookShelfCatalog.collectionID(forSeries: "ser_1")
        let serverA = CollectionModel(id: server, name: "Murderbot", bookIDs: [one.id], dateCreated: Date(timeIntervalSince1970: 300))
        let serverB = CollectionModel(id: server, name: "Murderbot", bookIDs: [], dateCreated: Date(timeIntervalSince1970: 50))
        for collection in [older, newer, serverA, serverB] { context.insert(collection) }
        manager.swiftDataController.save()
        manager.fetchCollections()

        #expect(manager.mergeDuplicateSeriesCollections())
        #expect(manager.collections.count == 2)
        let mistborn = try #require(manager.collections.first { $0.hardcoverSeriesID == 7 })
        #expect(mistborn.dateCreated == older.dateCreated)
        #expect(mistborn.bookIDs == [one.id, two.id])
        #expect(mistborn.autoContinue)
        let murderbot = try #require(manager.collections.first { $0.id == server })
        #expect(murderbot.dateCreated == serverB.dateCreated)
        #expect(murderbot.bookIDs == [one.id])
        #expect(!manager.mergeDuplicateSeriesCollections())
    }

    @Test("A series Collection that arrives before its books survives reconcile")
    func survivesHalfSync() {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let pending = UUID()
        manager.swiftDataController.context.insert(
            CollectionModel(name: "Mistborn", hardcoverSeriesID: 9, bookIDs: [pending])
        )
        manager.swiftDataController.save()
        manager.fetchCollections()

        manager.reconcileSeriesCollections()
        #expect(manager.collections.first?.bookIDs == [pending])
    }

    @Test("Unlinking a book from Hardcover takes it out of its series, and the series with its last book")
    func leavesOnUnlink() throws {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "The Final Empire")
        manager.swiftDataController.context.insert(book)
        manager.swiftDataController.context.insert(
            CollectionModel(name: "Mistborn", hardcoverSeriesID: 9, bookIDs: [book.id])
        )
        manager.swiftDataController.save()
        manager.fetchCollections()

        manager.leaveSeriesCollections(book)
        #expect(manager.collections.isEmpty)
    }
}
