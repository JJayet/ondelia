import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class SwiftDataController {
    static let shared = SwiftDataController()
    
    private(set) var isLoaded = false
    private(set) var isLoading = true
    private(set) var loadErrorMessage: String?
    /// Set when a save fails. Progress and bookmarks live only in this store, so a silent
    /// failure loses them; the UI shows this and clears it.
    var saveErrorMessage: String?
    
    private var _container: ModelContainer?
    
    var container: ModelContainer {
        guard let container = _container else {
            fatalError("SwiftData container not initialized yet. Access after initialization only.")
        }
        return container
    }
    
    static let preview: SwiftDataController = inMemory()

    /// Fresh, already-loaded in-memory store (previews, tests).
    static func inMemory() -> SwiftDataController {
        let controller = SwiftDataController(initiallyLoad: false)
        do {
            let container = try controller.buildContainer(inMemory: true)
            controller._container = container
            controller.isLoaded = true
            controller.isLoading = false
        } catch {
            fatalError("In-memory SwiftData error: \(error)")
        }
        return controller
    }
    
    @MainActor
    var context: ModelContext {
        return container.mainContext
    }
    
    func initializeAsync() {
        Task { @MainActor in
            do {
                self.isLoading = true
                self.isLoaded = false
                self.loadErrorMessage = nil
                let container = try self.buildContainer(inMemory: false)
                #if DEBUG
                try UITestBootstrap.prepareIfRequested(container: container)
                #endif
                self._container = container
                self.isLoaded = true
                self.isLoading = false
                Log.store.debug("✅ SwiftData loaded successfully")
                // After the store is known good, so a broken store is never copied over a good backup.
                Task.detached(priority: .utility) {
                    DatabaseBackupService.backupIfDue(container: container)
                }
            } catch {
                Log.store.error("❌ SwiftData error: \(error)")
                self.isLoading = false
                self.isLoaded = false
                self.loadErrorMessage = error.localizedDescription
            }
        }
    }

    /// Suspends until the store has finished loading, or failed to.
    func whenLoaded() async {
        await waitUntil { self.isLoaded || self.loadErrorMessage != nil }
    }

    func retryInitialization() {
        guard !isLoading else { return }
        initializeAsync()
    }
    
    @MainActor
    func save() {
        guard let container = _container else { return }
        let context = container.mainContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log.store.error("❌ SwiftData save failed: \(error)")
            saveErrorMessage = error.localizedDescription
        }
    }
    
    init(initiallyLoad: Bool = true) {
        if initiallyLoad { initializeAsync() }
    }

    /// Settings toggle. Read once, when the container is built: switching needs a relaunch.
    static let iCloudSyncKey = "sync.iCloud"
    static let cloudKitContainerID = "iCloud.io.jayet.isora"

    static var isICloudSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: iCloudSyncKey) as? Bool ?? true
    }

    private func buildContainer(inMemory: Bool) throws -> ModelContainer {
        guard !inMemory, Self.isICloudSyncEnabled else {
            return try buildContainer(inMemory: inMemory, cloudKit: .none)
        }
        do {
            return try buildContainer(inMemory: false, cloudKit: .private(Self.cloudKitContainerID))
        } catch {
            // The store is the library. A missing entitlement or an unsupported model must not
            // stop the app from opening it; it opens without sync instead.
            Log.store.error("❌ SwiftData: CloudKit store refused, opening locally: \(error)")
            return try buildContainer(inMemory: false, cloudKit: .none)
        }
    }

    private func buildContainer(
        inMemory: Bool,
        cloudKit: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: IsoraCurrentSchema.self)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: IsoraMigrationPlan.self,
            configurations: [modelConfiguration]
        )
    }
}
