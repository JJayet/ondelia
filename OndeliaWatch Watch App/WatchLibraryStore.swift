import Foundation
import SwiftData

/// The watch's own SwiftData store. Nothing is shared with the iPhone store — the watch only
/// ever holds what the phone sent it — so this is the whole persistence layer on this side.
///
/// `SwiftDataController` is not reused: it pulls in SwiftUI and the UI-test bootstrap.
@MainActor
@Observable
final class WatchLibraryStore {
    static let shared = WatchLibraryStore()

    let container: ModelContainer

    var context: ModelContext { container.mainContext }

    /// Every write on this side goes through here. A failed save used to be a `try?`, which is
    /// how a watch quietly stops remembering where the listener is.
    static func save() {
        do {
            try shared.context.save()
        } catch {
            Log.store.error("❌ WatchLibraryStore: save failed: \(error.localizedDescription)")
        }
    }

    private init() {
        let schema = Schema(versionedSchema: IsoraCurrentSchema.self)
        // Default location: the watch app's own Application Support, same as the phone store.
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: IsoraMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema)
            )
        } catch {
            Log.store.error("❌ WatchLibraryStore: \(error.localizedDescription)")
            // Without a store there is no app; an in-memory one at least keeps it running.
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("WatchLibraryStore: no store at all: \(error)")
            }
        }
    }
}
