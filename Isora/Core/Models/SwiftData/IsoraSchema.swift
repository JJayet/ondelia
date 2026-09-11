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

/// Version 3 adds windowed transcripts as a new entity. Only additions are possible here: the
/// model classes are shared between versions, so changing one would give two versions the same
/// checksum and SwiftData refuses to open the store.
enum IsoraSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IsoraSchemaV2.models + [TranscriptWindowModel.self]
    }
}

/// The schema every store (phone, watch, tests) is built from.
typealias IsoraCurrentSchema = IsoraSchemaV3

enum IsoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [IsoraSchemaV1.self, IsoraSchemaV2.self, IsoraSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: IsoraSchemaV1.self, toVersion: IsoraSchemaV2.self),
            .lightweight(fromVersion: IsoraSchemaV2.self, toVersion: IsoraSchemaV3.self)
        ]
    }
}
