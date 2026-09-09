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
            ChapterTranscriptionModel.self,
            CollectionModel.self
        ]
    }
}

/// Version 2 adds the listening log. Nothing else changes, so the migration is lightweight.
enum IsoraSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IsoraSchemaV1.models + [ListeningSessionModel.self]
    }
}

/// The schema every store (phone, watch, tests) is built from.
typealias IsoraCurrentSchema = IsoraSchemaV2

enum IsoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [IsoraSchemaV1.self, IsoraSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: IsoraSchemaV1.self, toVersion: IsoraSchemaV2.self)]
    }
}
