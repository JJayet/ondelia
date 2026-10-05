//
//  AudiobookShelfAPITests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("AudiobookShelf API")
struct AudiobookShelfAPITests {
    @Test("Server input is trimmed, gets https when bare, and keeps a proxy path")
    func serverURL() {
        #expect(AudiobookShelfAPI.serverURL(from: " abs.example.com/ ")?.absoluteString == "https://abs.example.com")
        #expect(AudiobookShelfAPI.serverURL(from: "http://192.168.1.2:13378")?.absoluteString == "http://192.168.1.2:13378")
        #expect(AudiobookShelfAPI.serverURL(from: "https://host/abs//")?.absoluteString == "https://host/abs")
        #expect(AudiobookShelfAPI.serverURL(from: "") == nil)
        #expect(AudiobookShelfAPI.serverURL(from: "ftp://host") == nil)
    }

    @Test("The Port field replaces a typed port and is range-checked")
    func serverURLPort() {
        #expect(AudiobookShelfAPI.serverURL(from: "http://nas.local", port: 13378)?.absoluteString == "http://nas.local:13378")
        #expect(AudiobookShelfAPI.serverURL(from: "nas.local:80/abs", port: 8443)?.absoluteString == "https://nas.local:8443/abs")
        #expect(AudiobookShelfAPI.serverURL(from: "nas.local", port: 0) == nil)
        #expect(AudiobookShelfAPI.serverURL(from: "nas.local", port: 70000) == nil)
    }

    @Test("A server's id ignores case, default ports and trailing slashes, not the username")
    func accountID() throws {
        let id = { (url: String, user: String) in
            AudiobookShelfAccount.id(server: try #require(URL(string: url)), username: user)
        }
        #expect(try id("https://ABS.example.com", "jo") == id("https://abs.example.com:443/", "jo"))
        #expect(try id("http://nas:13378", "jo") != id("http://nas:13379", "jo"))
        #expect(try id("https://abs.example.com", "jo") != id("https://abs.example.com", "ann"))
        #expect(try UUID(uuidString: id("https://abs.example.com", "jo")) != nil)
    }

    @Test("Items URL pages by title under the server path")
    func itemsURL() throws {
        let server = try #require(URL(string: "https://host/abs"))
        let url = AudiobookShelfAPI.itemsURL(server: server, library: "lib1", page: 2)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/abs/api/libraries/lib1/items")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["page"] == "2")
        #expect(query["limit"] == String(AudiobookShelfAPI.pageSize))
        #expect(query["sort"] == "media.metadata.title")
    }

    @Test("The author comes from the minified list or from search's expanded authors")
    func authorShapes() throws {
        let minified = #"{"id":"a","media":{"metadata":{"title":"Dune","authorName":"Frank Herbert"},"duration":3600}}"#
        let expanded = #"{"id":"b","media":{"metadata":{"title":"Good Omens","authors":[{"name":"Terry Pratchett"},{"name":"Neil Gaiman"}]}}}"#
        let decoder = JSONDecoder()
        let first = try decoder.decode(AudiobookShelfAPI.Item.self, from: Data(minified.utf8))
        let second = try decoder.decode(AudiobookShelfAPI.Item.self, from: Data(expanded.utf8))
        #expect(first.author == "Frank Herbert")
        #expect(first.media.duration == 3600)
        #expect(second.author == "Terry Pratchett, Neil Gaiman")
        #expect(second.media.duration == nil)
    }

    @Test("Server filenames cannot leave the download folder")
    func safeFilename() {
        #expect(AudiobookShelfAPI.safeFilename("Dune.zip") == "Dune.zip")
        #expect(AudiobookShelfAPI.safeFilename("../../etc/passwd") == "download..-..-etc-passwd")
        #expect(AudiobookShelfAPI.safeFilename("") == "download")
    }

    @Test("A finished download keeps the server's filename; an error page is refused")
    func keepDownload() throws {
        let url = try #require(URL(string: "https://host/api/items/a/download"))
        func downloaded() throws -> URL {
            let file = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data("zip".utf8).write(to: file)
            return file
        }

        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
            "Content-Disposition": #"attachment; filename="Dune.zip""#
        ])
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = try AudiobookShelfAPI.keepDownload(at: try downloaded(), response: ok, item: "li_a", in: root)
        #expect(kept.lastPathComponent == "Dune.zip")
        #expect(FileManager.default.fileExists(atPath: kept.path))

        let denied = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)
        #expect(throws: AudiobookShelfAPI.Failure.self) {
            try AudiobookShelfAPI.keepDownload(at: try downloaded(), response: denied, item: "li_a", in: root)
        }

        // What the next launch finds if the app is killed before the import runs.
        let empty = root.appending(path: "li_b/interrupted")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let pending = AudiobookShelfAPI.pendingDownloads(in: root)
        #expect(pending.map(\.item) == ["li_a"])
        #expect(pending.map(\.file) == [kept])
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "li_b").path))
    }

    @Test("Progress has a fraction only when the size is known")
    @MainActor func progressFraction() {
        typealias Progress = AudiobookShelfService.DownloadProgress
        #expect(Progress(received: 50, expected: 200).fraction == 0.25)
        #expect(Progress(received: 50, expected: nil).fraction == nil)
        #expect(Progress(received: 300, expected: 200).fraction == 1)
    }

    @Test("A task description round-trips id, account and title, and older ones still parse")
    func taskDescription() {
        let described = AudiobookShelfDownloader.describe(id: "li_a", account: "acc", title: "Dune\nMessiah")
        #expect(AudiobookShelfDownloader.parse(described)?.id == "li_a")
        #expect(AudiobookShelfDownloader.parse(described)?.account == "acc")
        #expect(AudiobookShelfDownloader.parse(described)?.title == "Dune\nMessiah")
        #expect(AudiobookShelfDownloader.parse("li_a\nDune")?.account == nil)
        #expect(AudiobookShelfDownloader.parse("li_a\nDune")?.title == "Dune")
        #expect(AudiobookShelfDownloader.parse("li_a")?.id == "li_a")
        #expect(AudiobookShelfDownloader.parse("li_a")?.title == "")
        #expect(AudiobookShelfDownloader.parse(nil) == nil)
    }
}

@MainActor
@Suite("AudiobookShelf accounts")
struct AudiobookShelfAccountTests {
    @Test("The single account's keys become the first account, with its server library")
    func legacyAccount() throws {
        let suite = "abs-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AudiobookShelfService.legacyAccount(defaults: defaults) == nil)

        defaults.set("http://nas:13378", forKey: AudiobookShelfService.Defaults.server)
        defaults.set("jo", forKey: AudiobookShelfService.Defaults.username)
        defaults.set("lib_1", forKey: AudiobookShelfService.Defaults.library)
        let account = try #require(AudiobookShelfService.legacyAccount(defaults: defaults))
        #expect(account.server.absoluteString == "http://nas:13378")
        #expect(account.library == "lib_1")
        #expect(account.id == AudiobookShelfAccount.id(server: account.server, username: "jo"))
    }
}
