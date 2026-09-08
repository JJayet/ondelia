import Foundation
import Testing
@testable import Isora

@MainActor
@Suite("Collections")
struct CollectionGroupTests {
    private func book(
        _ title: String,
        series: String? = nil,
        position: Double? = nil,
        duration: Double = 3600,
        at seconds: Double = 0,
        bookID: Int = 0,
        seriesID: Int? = 1
    ) -> AudiobookModel {
        let model = AudiobookModel(title: title, duration: duration, currentPosition: seconds)
        if let series {
            model.hardcover = HardcoverLink(
                id: bookID == 0 ? abs(title.hashValue % 100_000) : bookID,
                title: title,
                author: "Author",
                seriesID: seriesID,
                seriesName: series,
                seriesPosition: position,
                seriesChecked: true
            )
        }
        return model
    }

    /// A manager over a fresh store holding these books, with series collections reconciled.
    private func manager(with books: [AudiobookModel]) -> AudiobookManager {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        for book in books { manager.swiftDataController.context.insert(book) }
        manager.fetchAudiobooks()
        return manager
    }

    @Test("A Hardcover series becomes a collection, volumes in reading order")
    func seriesBecomesCollection() {
        UserDefaults.standard.removeObject(forKey: AudiobookManager.autoSeriesCollectionsKey)
        let third = book("Hero of Ages", series: "Mistborn", position: 3)
        let first = book("The Final Empire", series: "Mistborn", position: 1)
        let unknown = book("Secret History", series: "Mistborn")
        let sapiens = book("Sapiens")
        let manager = manager(with: [third, first, unknown, sapiens])

        #expect(manager.collections.count == 1)
        let series = manager.collections[0]
        #expect(series.name == "Mistborn")
        #expect(series.hardcoverSeriesID == 1)
        #expect(series.bookIDs == [first.id, third.id, unknown.id])

        let groups = CollectionGroup.build(collections: manager.collections, audiobooks: manager.audiobooks, keepEmpty: true)
        #expect(groups.first?.books.map(\.title) == ["The Final Empire", "Hero of Ages", "Secret History"])
    }

    @Test("Automatic grouping off: the series is offered once, not created")
    func seriesIsOfferedWhenAutoIsOff() {
        UserDefaults.standard.set(false, forKey: AudiobookManager.autoSeriesCollectionsKey)
        UserDefaults.standard.removeObject(forKey: "library.declinedSeriesCollections")
        defer {
            UserDefaults.standard.removeObject(forKey: AudiobookManager.autoSeriesCollectionsKey)
            UserDefaults.standard.removeObject(forKey: "library.declinedSeriesCollections")
        }
        let manager = manager(with: [book("Dune", series: "Dune", position: 1, seriesID: 7)])

        #expect(manager.collections.isEmpty)
        let prompt = manager.collectionPrompt
        #expect(prompt?.name == "Dune")

        manager.respondToCollectionPrompt(prompt!, create: false)
        manager.reconcileSeriesCollections()
        #expect(manager.collectionPrompt == nil)
        #expect(manager.collections.isEmpty)
    }

    @Test("Hand-made collections: a book can be in several, and leaves them when deleted")
    func manualCollections() {
        UserDefaults.standard.removeObject(forKey: AudiobookManager.autoSeriesCollectionsKey)
        let a = book("A"), b = book("B")
        let manager = manager(with: [a, b])

        let favourites = manager.createCollection(name: "  Favourites ", books: [a])!
        let commute = manager.createCollection(name: "Commute", books: [a, b])!
        #expect(favourites.name == "Favourites")
        #expect(manager.createCollection(name: "   ", books: [a]) == nil)

        let groups = CollectionGroup.build(collections: manager.collections, audiobooks: manager.audiobooks, keepEmpty: true)
        #expect(groups.map(\.name) == ["Commute", "Favourites"])

        manager.remove(a, from: commute)
        #expect(commute.bookIDs == [b.id])
        manager.removeFromAllCollections(bookID: a.id)
        #expect(favourites.bookIDs.isEmpty)
    }

    @Test("Progress is weighted by length and the current book is the one in progress")
    func progressAndCurrent() {
        let done = book("One", duration: 1000, at: 1000)
        done.isFinished = true
        let reading = book("Two", duration: 3000, at: 600)
        let group = CollectionGroup(collection: CollectionModel(name: "Saga", bookIDs: [done.id, reading.id]), books: [done, reading])

        #expect(group.totalDuration == 4000)
        #expect(group.progressFraction == 0.4)
        #expect(group.currentBook?.title == "Two")
    }

    @Test("The catalogue fills in missing volumes only when asked")
    func catalogueMarksMissingVolumes() throws {
        let seriesID = 9_001
        defer { SeriesCatalog.store([], for: seriesID) }
        SeriesCatalog.store(
            [SeriesVolume(bookID: 11, title: "One", position: 1), SeriesVolume(bookID: 22, title: "Two", position: 2)],
            for: seriesID
        )
        let owned = book("One", series: "Saga", position: 1, bookID: 11, seriesID: seriesID)
        let group = CollectionGroup(
            collection: CollectionModel(name: "Saga", hardcoverSeriesID: seriesID, bookIDs: [owned.id]),
            books: [owned]
        )

        let shown = group.volumes(showMissing: true)
        #expect(shown.count == 2)
        #expect(group.catalogueCount == 2)
        guard case .owned(let first) = shown[0], case .missing(let second) = shown[1] else {
            Issue.record("Expected the owned volume first and the missing one after it")
            return
        }
        #expect(first.title == "One")
        #expect(second.title == "Two")
        #expect(group.volumes(showMissing: false).count == 1)
    }

    @Test("Volume badges round whole positions and keep halves")
    func volumeBadges() {
        func badge(_ position: Double?) -> String? {
            HardcoverLink(id: 1, title: "t", author: "a", seriesPosition: position).volumeBadge
        }
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(badge(1) == "#1")
        #expect(badge(1.5) == "#1\(separator)5")
        #expect(badge(nil) == nil)
    }
}
