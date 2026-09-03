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

    func retryInitialization() {
        guard !isLoading else { return }
        initializeAsync()
    }
    
    @MainActor
    func save() {
        guard let container = _container else { return }
        let context = container.mainContext
        guard context.hasChanges else { return }
        do { try context.save() } catch { Log.store.debug("Save error: \(error)") }
    }
    
    init(initiallyLoad: Bool = true) {
        if initiallyLoad { initializeAsync() }
    }

    private func buildContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([
            AudiobookModel.self,
            BookmarkModel.self,
            ChapterModel.self,
            ChapterTranscriptionModel.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}
