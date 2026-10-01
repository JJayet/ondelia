import Testing
import Foundation
import SwiftData
@testable import Isora

@MainActor
struct DatabaseBackupServiceTests {
    @Test("A backup of the current store still opens with the migration plan")
    func backupKeepsVersionedSchema() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: "default.store")
        let schema = Schema(versionedSchema: IsoraCurrentSchema.self)
        let id = UUID()
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: IsoraMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)]
            )
            container.mainContext.insert(AudiobookModel(id: id, title: "Dune"))
            container.mainContext.insert(CollectionModel(name: "Sci-fi"))
            try container.mainContext.save()
        }

        let backup = try #require(DatabaseBackupService.backUp(storeURL: storeURL))
        defer { try? FileManager.default.removeItem(at: backup) }
        let copy = backup.appending(path: storeURL.lastPathComponent)

        let restored = try ModelContainer(
            for: schema,
            migrationPlan: IsoraMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: copy, cloudKitDatabase: .none)]
        )
        #expect(try restored.mainContext.fetch(FetchDescriptor<AudiobookModel>()).map(\.id) == [id])
        #expect(try restored.mainContext.fetchCount(FetchDescriptor<CollectionModel>()) == 1)
    }

    @Test("A file that is not a database fails validation")
    func garbageFailsValidation() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not sqlite".utf8).write(to: url)
        #expect(!DatabaseBackupService.validate(url))
    }
}
