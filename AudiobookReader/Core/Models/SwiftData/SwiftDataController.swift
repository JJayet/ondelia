import Foundation
import SwiftData
import SwiftUI

class SwiftDataController: ObservableObject {
    static let shared = SwiftDataController()
    
    @Published private(set) var isLoaded = false
    @Published private(set) var isLoading = true
    
    private var _container: ModelContainer?
    
    var container: ModelContainer {
        guard let container = _container else {
            fatalError("SwiftData container not initialized yet. Access after initialization only.")
        }
        return container
    }
    
    static let preview: SwiftDataController = {
        let controller = SwiftDataController(initiallyLoad: false)
        do {
            let container = try controller.buildContainer(inMemory: true)
            controller._container = container
            controller.isLoaded = true
            controller.isLoading = false
        } catch {
            fatalError("Preview SwiftData error: \(error)")
        }
        return controller
    }()
    
    @MainActor
    var context: ModelContext {
        return container.mainContext
    }
    
    func initializeAsync() {
        Task { @MainActor in
            do {
                self.isLoading = true
                let container = try self.buildContainer(inMemory: false)
                self._container = container
                self.isLoaded = true
                self.isLoading = false
                print("✅ SwiftData loaded successfully")
            } catch {
                print("❌ SwiftData error: \(error)")
                self.isLoading = false
                fatalError("Failed to create SwiftData container: \(error)")
            }
        }
    }
    
    @MainActor
    func save() {
        let context = container.mainContext
        guard context.hasChanges else { return }
        do { try context.save() } catch { print("Save error: \(error)") }
    }
    
    func backgroundContext() -> ModelContext {
        return ModelContext(container)
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
