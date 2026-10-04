//
//  AudiobookShelfBrowseTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("AudiobookShelf browsing")
struct AudiobookShelfBrowseTests {
    private func item(_ json: String) throws -> AudiobookShelfAPI.Item {
        try JSONDecoder().decode(AudiobookShelfAPI.Item.self, from: Data(json.utf8))
    }

    @Test("A series decodes as one object or as a list, and a folded series is kept")
    func seriesShapes() throws {
        let filtered = try item(#"{"id":"a","media":{"metadata":{"title":"A","series":{"id":"s","name":"Dune","sequence":"2"}}}}"#)
        let expanded = try item(#"{"id":"b","media":{"metadata":{"title":"B","series":[{"id":"s","name":"Dune","sequence":"3"}]}}}"#)
        let collapsed = try item(#"{"id":"c","media":{"metadata":{"title":"C"}},"collapsedSeries":{"id":"s","name":"Dune","numBooks":6}}"#)
        #expect(filtered.sequence == "2")
        #expect(expanded.sequence == "3")
        #expect(collapsed.sequence == nil)
        #expect(collapsed.collapsedSeries?.numBooks == 6)
    }

    @Test("Series order sorts numbers as numbers and puts unnumbered books last")
    func sequenceOrder() throws {
        func book(_ id: String, _ sequence: String?) throws -> AudiobookShelfAPI.Item {
            let series = sequence.map { #","series":{"id":"s","sequence":"\#($0)"}"# } ?? ""
            return try item(#"{"id":"\#(id)","media":{"metadata":{"title":"\#(id)"\#(series)}}}"#)
        }
        let books = try [book("ten", "10"), book("none", nil), book("two", "2"), book("half", "1.5")]
        #expect(books.sorted(by: AudiobookShelfAPI.Item.bySequence).map(\.id) == ["half", "two", "ten", "none"])
    }

    @Test("A series filter escapes base64's + / and =, which the server would misread")
    func seriesFilterEscaping() throws {
        let server = try #require(URL(string: "https://host"))
        // "s>?" encodes to "cz4/" and "s>>" to "cz4+": both characters must reach the server intact.
        let slash = try #require(AudiobookShelfAPI.seriesItemsURL(server: server, library: "l", series: "s>?"))
        let plus = try #require(AudiobookShelfAPI.seriesItemsURL(server: server, library: "l", series: "s>>"))
        let padded = try #require(AudiobookShelfAPI.seriesItemsURL(server: server, library: "l", series: "s"))
        #expect(slash.absoluteString.contains("filter=series.cz4%2F"))
        #expect(plus.absoluteString.contains("filter=series.cz4%2B"))
        #expect(padded.absoluteString.contains("filter=series.cw%3D%3D"))
    }

    @Test("Folding series is asked for only when wanted")
    func collapseQuery() throws {
        let server = try #require(URL(string: "https://host"))
        let folded = AudiobookShelfAPI.itemsURL(server: server, library: "l", page: 0, collapseSeries: true)
        let flat = AudiobookShelfAPI.itemsURL(server: server, library: "l", page: 0)
        #expect(folded.absoluteString.contains("collapseseries=1"))
        #expect(!flat.absoluteString.contains("collapseseries"))
    }

    struct Row: Identifiable { let id: Int }

    @Test("The pager asks for the next page only from the last row, and stops at the total")
    @MainActor func pager() async {
        var asked: [Int] = []
        let pager = AudiobookShelfPager<Row> { page in
            asked.append(page)
            return ((page * 2..<page * 2 + 2).map(Row.init), 3)
        }
        await pager.loadMore()
        await pager.loadMore(after: Row(id: 0))  // not the last row: ignored
        await pager.loadMore(after: Row(id: 1))
        await pager.loadMore(after: Row(id: 3))  // total reached: ignored
        #expect(asked == [0, 1])
        #expect(pager.items.map(\.id) == [0, 1, 2, 3])
        #expect(pager.isExhausted)
    }
}

@Suite("AudiobookShelf server collections")
struct AudiobookShelfCollectionTests {
    @Test("Collections decode as series flagged as collections, books in the server's order")
    func decoding() throws {
        // Shape taken from AudiobookShelf 2.x: expanded library items.
        let json = """
        {"results":[{"id":"col_1","libraryId":"lib","name":"Favourites","books":[
          {"id":"li_b","media":{"metadata":{"title":"Hyperion","authors":[{"id":"x","name":"Dan Simmons"}]},"duration":60}},
          {"id":"li_a","media":{"metadata":{"title":"Dune","authors":[{"id":"y","name":"Frank Herbert"}]},"duration":90}}
        ]}],"total":1}
        """
        let decoded = try JSONDecoder().decode(AudiobookShelfAPI.CollectionsResponse.self, from: Data(json.utf8)).series
        #expect(decoded.map(\.name) == ["Favourites"])
        #expect(decoded.first?.isServerCollection == true)
        #expect(decoded.first?.books?.map(\.id) == ["li_b", "li_a"])
        #expect(decoded.first?.books?.first?.author == "Dan Simmons")
    }

    @Test("A collection and a series with the same id stand for different Collections")
    func collectionIDs() {
        let series = AudiobookShelfAPI.Series(id: "x", name: "S")
        let collection = AudiobookShelfAPI.Series(id: "x", name: "C", isCollection: true)
        #expect(AudiobookShelfCatalog.collectionID(for: series) == AudiobookShelfCatalog.collectionID(forSeries: "x"))
        #expect(AudiobookShelfCatalog.collectionID(for: collection) != AudiobookShelfCatalog.collectionID(for: series))
        #expect(collection.hiddenKind == .collection)
    }
}
