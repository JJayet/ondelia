import Foundation
import Testing
@testable import AudiobookReader

@Suite("Series grouping")
struct SeriesGroupTests {

    @MainActor
    private func book(
        _ title: String,
        series: String? = nil,
        position: Double? = nil,
        duration: Double = 3600,
        at seconds: Double = 0,
        bookID: Int = 0,
        seriesID: Int? = nil
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

    @MainActor
    @Test("Books sharing a series are grouped in volume order")
    func groupsInVolumeOrder() {
        let third = book("Hero of Ages", series: "Mistborn", position: 3)
        let first = book("The Final Empire", series: "Mistborn", position: 1)
        let second = book("Well of Ascension", series: "Mistborn", position: 2)

        let result = SeriesGroup.group([third, first, second])

        #expect(result.standalone.isEmpty)
        #expect(result.series.count == 1)
        #expect(result.series.first?.books.map { $0.title } == ["The Final Empire", "Well of Ascension", "Hero of Ages"])
    }

    @MainActor
    @Test("A single owned volume still forms its series")
    func lonelyVolumeIsStillASeries() {
        let dune = book("Dune", series: "Dune", position: 1)
        let sapiens = book("Sapiens")

        let result = SeriesGroup.group([dune, sapiens])

        #expect(result.series.map { $0.name } == ["Dune"])
        #expect(result.series.first?.books.map { $0.title } == ["Dune"])
        #expect(result.standalone.map { $0.title } == ["Sapiens"])
    }

    @MainActor
    @Test("The standalone shelf keeps the order it was sorted in")
    func standaloneKeepsOrder() {
        let a = book("A")
        let b = book("B", series: "Trilogy", position: 1)
        let c = book("C")
        let d = book("D", series: "Trilogy", position: 2)

        let result = SeriesGroup.group([a, b, c, d])

        #expect(result.standalone.map { $0.title } == ["A", "C"])
        #expect(result.series.first?.name == "Trilogy")
    }

    @MainActor
    @Test("Volumes Hardcover has no position for sort last, by title")
    func unpositionedVolumesSortLast() {
        let unknown = book("Zero", series: "Saga")
        let first = book("One", series: "Saga", position: 1)

        let result = SeriesGroup.group([unknown, first])

        #expect(result.series.first?.books.map { $0.title } == ["One", "Zero"])
    }

    @MainActor
    @Test("Series progress is weighted by length, not by volume count")
    func progressIsWeightedByLength() {
        let long = book("Long", series: "Saga", position: 1, duration: 3000, at: 3000)
        let short = book("Short", series: "Saga", position: 2, duration: 1000, at: 0)

        let group = SeriesGroup.group([long, short]).series.first

        #expect(group?.totalDuration == 4000)
        #expect(group?.progressFraction == 0.75)
    }

    @MainActor
    @Test("The current volume is the one in progress")
    func currentVolumeIsTheOneInProgress() {
        let done = book("One", series: "Saga", position: 1, duration: 1000, at: 1000)
        done.isFinished = true
        let reading = book("Two", series: "Saga", position: 2, duration: 1000, at: 400)
        let untouched = book("Three", series: "Saga", position: 3)

        let group = SeriesGroup.group([done, reading, untouched]).series.first

        #expect(group?.currentBook?.title == "Two")
    }

    @MainActor
    @Test("The catalogue fills in the volumes the shelf does not hold")
    func catalogueMarksMissingVolumes() throws {
        let seriesID = 9_001
        defer { SeriesCatalog.store([], for: seriesID) }
        SeriesCatalog.store(
            [
                SeriesVolume(bookID: 11, title: "One", position: 1),
                SeriesVolume(bookID: 22, title: "Two", position: 2)
            ],
            for: seriesID
        )

        let owned = book("One", series: "Saga", position: 1, bookID: 11, seriesID: seriesID)
        let group = try #require(SeriesGroup.group([owned]).series.first)
        let volumes = group.volumes

        #expect(volumes.count == 2)
        #expect(group.catalogueCount == 2)
        guard case .owned(let first) = volumes[0], case .missing(let second) = volumes[1] else {
            Issue.record("Expected the owned volume first and the missing one after it")
            return
        }
        #expect(first.title == "One")
        #expect(second.title == "Two")
    }

    @MainActor
    @Test("A shelf volume the catalogue does not list is still shown")
    func unlistedOwnedVolumeSurvives() throws {
        let seriesID = 9_002
        defer { SeriesCatalog.store([], for: seriesID) }
        SeriesCatalog.store([SeriesVolume(bookID: 11, title: "One", position: 1)], for: seriesID)

        let owned = book("Other edition", series: "Saga", position: 2, bookID: 99, seriesID: seriesID)
        let group = try #require(SeriesGroup.group([owned]).series.first)

        #expect(group.volumes.count == 2)
    }

    @MainActor
    @Test("With no catalogue the card still lists what is owned")
    func fallsBackToOwnedVolumes() {
        let first = book("One", series: "Saga", position: 1)
        let second = book("Two", series: "Saga", position: 2)

        let group = SeriesGroup.group([first, second]).series.first

        #expect(group?.volumes.count == 2)
        #expect(group?.catalogueCount == nil)
    }

    @Test("Volume badges round whole positions and keep halves")
    func volumeBadges() {
        func badge(_ position: Double?) -> String? {
            HardcoverLink(id: 1, title: "t", author: "a", seriesPosition: position).volumeBadge
        }
        // The half is formatted for the reader's locale, so "1,5" in French is correct.
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(badge(1) == "#1")
        #expect(badge(1.5) == "#1\(separator)5")
        #expect(badge(nil) == nil)
    }
}
