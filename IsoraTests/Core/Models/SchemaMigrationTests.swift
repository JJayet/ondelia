import Testing
import Foundation
import SwiftData
@testable import Isora

@MainActor
struct SchemaMigrationTests {
    @Test("Container built from the migration plan stores and fetches a book")
    func versionedContainerRoundTrips() throws {
        let schema = Schema(versionedSchema: IsoraSchemaV1.self)
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
}
