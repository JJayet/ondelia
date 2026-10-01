import Testing
import Foundation
import SwiftData
import CoreData
@testable import Isora

@MainActor
struct SchemaMigrationTests {
    @Test("Container built from the migration plan stores and fetches a book")
    func versionedContainerRoundTrips() throws {
        let schema = Schema(versionedSchema: IsoraCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: IsoraMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext

        let id = UUID()
        context.insert(AudiobookModel(id: id, title: "Dune", author: "Herbert"))
        try context.save()

        let books = try context.fetch(FetchDescriptor<AudiobookModel>())
        #expect(books.count == 1)
        #expect(books.first?.id == id)
        #expect(books.first?.title == "Dune")
    }

    /// Hashes of every entity as shipped stores hold them, one entry per entity, taken from
    /// schema V4. Changing a model class that an earlier version lists changes its hash, and a
    /// store written by the released app then matches no version: SwiftData refuses to open it
    /// ("Cannot use staged migration with an unknown model version"). Add a new entity in a new
    /// version instead; only then add its hash here.
    static let shippedEntityHashes: [String: String] = [
        "AudiobookModel": "3s9I63Vn2ai2Qal6du88xDrLoVcDqM36WmM2WN0EWVo=",
        "AudiobookShelfLinkModel": "3W0e2q0tS0NdXcvyWn5qGyL3Sttoql56O27WzJOyooc=",
        "BookmarkModel": "egR8UekHQnoF77suqvRC67a1vkoTTSTzx+WuI/au0F0=",
        "ChapterModel": "rKqBj9eJlgMK3daNSzSq8FkksgVjGNHmZWbWQfmt6FQ=",
        "ChapterTranscriptionModel": "K8AI3+DzTKtnvtCSt4MbotKWks6FtKblV7vp3reTWMc=",
        "CollectionModel": "jbrLGOvFz3d6YQ/jikx55Yp+EU1SzFATltepfA5/btw=",
        "ListeningSessionModel": "VfD4JzNW0cYCwa4mcueuXH3Ze83Ud5DquJ5QXWBh11U=",
        "TranscriptWindowModel": "/MPyjALvB7iE3ED8Kxrgnnx89VQJhQmZJsXso10za78="
    ]

    @Test("Entities of released schema versions keep the hash stores were written with")
    func entityHashesArePinned() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: IsoraCurrentSchema.models))
        let hashes = model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        #expect(hashes == Self.shippedEntityHashes, "current: \(hashes.sorted { $0.key < $1.key })")
    }

    @Test("A store written with schema V3 opens with the current plan")
    func v3StoreMigrates() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let id = UUID()
        do {
            let schema = Schema(versionedSchema: IsoraSchemaV3.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            container.mainContext.insert(AudiobookModel(id: id, title: "Dune"))
            try container.mainContext.save()
        }

        let schema = Schema(versionedSchema: IsoraCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: IsoraMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let books = try container.mainContext.fetch(FetchDescriptor<AudiobookModel>())
        #expect(books.map(\.id) == [id])
        container.mainContext.insert(AudiobookShelfLinkModel(audiobookID: id, itemID: "li_a"))
        try container.mainContext.save()
    }

    @Test("A store migrated to an unversioned partial schema is repaired and opens with the plan")
    func unversionedStoreIsRepaired() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let schema = Schema(versionedSchema: IsoraCurrentSchema.self)
        let id = UUID()
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: IsoraMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            container.mainContext.insert(AudiobookModel(id: id, title: "Dune"))
            try container.mainContext.save()
        }
        // What the old backup validation did to every backup.
        do {
            let partial = Schema([
                AudiobookModel.self,
                BookmarkModel.self,
                ChapterModel.self,
                ChapterTranscriptionModel.self,
                TranscriptWindowModel.self
            ])
            _ = try ModelContainer(
                for: partial,
                configurations: [ModelConfiguration(schema: partial, url: url, cloudKitDatabase: .none)]
            )
        }
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        #expect(throws: (any Error).self) {
            _ = try ModelContainer(for: schema, migrationPlan: IsoraMigrationPlan.self, configurations: [configuration])
        }

        try SwiftDataController.repairUnversionedStore(at: url)

        let container = try ModelContainer(
            for: schema,
            migrationPlan: IsoraMigrationPlan.self,
            configurations: [configuration]
        )
        #expect(try container.mainContext.fetch(FetchDescriptor<AudiobookModel>()).map(\.id) == [id])
        container.mainContext.insert(CollectionModel(name: "Sci-fi"))
        try container.mainContext.save()
    }
}
