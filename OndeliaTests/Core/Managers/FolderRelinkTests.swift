//
//  FolderRelinkTests.swift
//  IsoraTests
//

import Foundation
import Testing
@testable import Isora

@MainActor
@Suite("Folder relink", .tags(.manager))
struct FolderRelinkTests {
    @Test("A copied folder fills the entry that points at it, unless the length disagrees")
    func awaitingFolder() {
        let manager = AudiobookManager(swiftDataController: .inMemory())
        let book = AudiobookModel(title: "Synced", fileURL: "Synced Folder", duration: 300)
        manager.swiftDataController.context.insert(book)
        manager.fetchAudiobooks()

        let folder = AudiobookModel.libraryFolderURL.appendingPathComponent("Synced Folder")
        #expect(manager.entryAwaitingFolder(at: folder, duration: 300.4)?.id == book.id)
        #expect(manager.entryAwaitingFolder(at: folder, duration: 250) == nil)
        #expect(manager.entryAwaitingFolder(at: folder.appendingPathComponent("x"), duration: 300) == nil)
    }

    @Test("Orphans are library items no book sits in")
    func orphans() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Book Folder"), withIntermediateDirectories: true)
        try Data(count: 10).write(to: root.appendingPathComponent("book.m4a"))
        try Data(count: 10).write(to: root.appendingPathComponent("stray.m4a"))

        let referenced = [root.appendingPathComponent("Book Folder/01.m4a"), root.appendingPathComponent("book.m4a")]
        let orphans = StorageUsage.orphans(in: root, referenced: referenced)
        #expect(orphans.map(\.lastPathComponent) == ["stray.m4a"])
    }
}
