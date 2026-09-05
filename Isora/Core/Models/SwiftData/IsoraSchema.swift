import Foundation
import SwiftData

/// Version 1 of the store: the shape that shipped before versioning existed.
///
/// The model classes stay top-level rather than nested inside this enum. Nesting is the
/// Apple-documented shape, but it would reindent four files and force typealiases for no
/// behaviour change; listing them here gives the same entity names and the same store.
enum IsoraSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AudiobookModel.self,
            BookmarkModel.self,
            ChapterModel.self,
            ChapterTranscriptionModel.self
        ]
    }
}

/// No stages yet — V1 is the only schema. Adding V2 means appending it to `schemas` and a
/// stage here; the container already routes through this plan.
enum IsoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [IsoraSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
