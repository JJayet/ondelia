//
//  StorageUsageTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@Suite("Storage usage", .tags(.manager))
struct StorageUsageTests {
    @Test("A file is its own size; a folder is the sum of its files; nothing is zero")
    func sizes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let one = root.appendingPathComponent("a.m4a")
        try Data(count: 1_000).write(to: one)
        try Data(count: 2_000).write(to: nested.appendingPathComponent("b.m4a"))

        #expect(StorageUsage.bytes(at: one) == 1_000)
        #expect(StorageUsage.bytes(at: root) == 3_000)
        #expect(StorageUsage.bytes(at: root.appendingPathComponent("missing")) == 0)
    }
}
