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

/// Version 4 adds the link from a book to the AudiobookShelf item it was downloaded from, as a
/// new entity for the same reason.
enum IsoraSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IsoraSchemaV3.models + [AudiobookShelfLinkModel.self]
    }
}

/// Version 5 records which Hardcover reads a Finish closed, as a new entity for the same reason.
enum IsoraSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IsoraSchemaV4.models + [HardcoverClosedReadModel.self]
    }
}

/// Version 6 records which AudiobookShelf server an item lives on and what the listener hid, as
/// new entities for the same reason.
enum IsoraSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IsoraSchemaV5.models + [AudiobookShelfItemServerModel.self, HiddenServerEntryModel.self]
    }
}

/// The schema every store (phone, watch, tests) is built from.
typealias IsoraCurrentSchema = IsoraSchemaV6

enum IsoraMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [IsoraSchemaV1.self, IsoraSchemaV2.self, IsoraSchemaV3.self, IsoraSchemaV4.self, IsoraSchemaV5.self,
         IsoraSchemaV6.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: IsoraSchemaV1.self, toVersion: IsoraSchemaV2.self),
            .lightweight(fromVersion: IsoraSchemaV2.self, toVersion: IsoraSchemaV3.self),
            .lightweight(fromVersion: IsoraSchemaV3.self, toVersion: IsoraSchemaV4.self),
            .lightweight(fromVersion: IsoraSchemaV4.self, toVersion: IsoraSchemaV5.self),
            .lightweight(fromVersion: IsoraSchemaV5.self, toVersion: IsoraSchemaV6.self)
        ]
    }
}
