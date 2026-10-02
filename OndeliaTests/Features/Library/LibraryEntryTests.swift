//
//  LibraryEntryTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("Library entries with server audiobooks")
@MainActor
struct LibraryEntryTests {
    private func item(_ id: String, _ title: String, author: String = "", addedAt: Double = 0) throws -> AudiobookShelfAPI.Item {
        let json = #"{"id":"\#(id)","addedAt":\#(addedAt),"media":{"metadata":{"title":"\#(title)","authorName":"\#(author)"}}}"#
        return try JSONDecoder().decode(AudiobookShelfAPI.Item.self, from: Data(json.utf8))
    }

    private func titles(_ entries: [LibraryEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .book(let book): book.title ?? ""
            case .server(let item): "s:" + item.title
            }
        }
    }

    @Test("By title, server audiobooks interleave and books keep their order")
    func byTitle() throws {
        let books = [AudiobookModel(title: "B", author: ""), AudiobookModel(title: "D", author: "")]
        let server = [try item("1", "E"), try item("2", "A"), try item("3", "C")]
        let merged = LibraryEntry.merged(books, AudiobookShelfCatalog.Sorted(server).items(for: .title), by: .title)
        #expect(titles(merged) == ["s:A", "B", "s:C", "D", "s:E"])
    }

    @Test("By recently played, server audiobooks come last, by title")
    func lastPlayed() throws {
        let books = [AudiobookModel(title: "Z", author: ""), AudiobookModel(title: "A", author: "")]
        let server = [try item("1", "Y"), try item("2", "B")]
        let merged = LibraryEntry.merged(books, AudiobookShelfCatalog.Sorted(server).items(for: .lastPlayed), by: .lastPlayed)
        #expect(titles(merged) == ["Z", "A", "s:B", "s:Y"])
    }

    @Test("A catalogue item survives the disk cache: author, series and date")
    func codableRoundTrip() throws {
        let json = #"{"id":"a","addedAt":1700000000000,"media":{"metadata":{"title":"Dune","authorName":"Frank Herbert","series":{"id":"s1","name":"Dune","sequence":"1"}},"duration":3600}}"#
        let item = try JSONDecoder().decode(AudiobookShelfAPI.Item.self, from: Data(json.utf8))
        let back = try JSONDecoder().decode(AudiobookShelfAPI.Item.self, from: JSONEncoder().encode(item))
        #expect(back == item)
        #expect(back.author == "Frank Herbert")
        #expect(back.sequence == "1")
    }

    @Test("By date added, the server's date places them, newest first")
    func dateAdded() throws {
        let now = Date()
        let books = [
            AudiobookModel(title: "New", author: "", dateAdded: now),
            AudiobookModel(title: "Old", author: "", dateAdded: now.addingTimeInterval(-1000))
        ]
        let middle = now.addingTimeInterval(-500).timeIntervalSince1970 * 1000
        let merged = LibraryEntry.merged(books, [try item("1", "Mid", addedAt: middle)], by: .dateAdded)
        #expect(titles(merged) == ["New", "s:Mid", "Old"])
    }
}

@Suite("Server series Collections")
struct ServerSeriesCollectionTests {
    @Test("A server series always derives the same Collection id, distinct per series")
    func collectionID() {
        let first = AudiobookShelfCatalog.collectionID(forSeries: "ser_1")
        #expect(first == AudiobookShelfCatalog.collectionID(forSeries: "ser_1"))
        #expect(first != AudiobookShelfCatalog.collectionID(forSeries: "ser_2"))
        // Name-based: version 5, RFC 4122 variant.
        #expect(first.uuidString.dropFirst(14).first == "5")
        #expect("89AB".contains(first.uuidString.dropFirst(19).first ?? "x"))
    }
}
