import Foundation
import CoreData

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    
    @Published var isLoaded = false
    @Published var isLoading = false
    
    private var _container: NSPersistentContainer?
    
    var container: NSPersistentContainer {
        if let container = _container {
            return container
        }
        
        let container = NSPersistentContainer(name: "AudiobookReader")
        _container = container
        
        // Pre-configure the container before loading stores
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Optimize Core Data performance
        container.viewContext.stalenessInterval = 0.0
        
        // Mark as loading and start async initialization
        Task { @MainActor in
            self.isLoading = true
        }
        
        // Load stores asynchronously on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            container.loadPersistentStores { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error as NSError? {
                        print("❌ Core Data error: \(error), \(error.userInfo)")
                    } else {
                        print("✅ Core Data loaded successfully")
                        self?.isLoaded = true
                    }
                }
            }
        }
        
        return container
    }
    
    var context: NSManagedObjectContext {
        return container.viewContext
    }
    
    /// Initialize Core Data asynchronously - call this early in app lifecycle
    func initializeAsync() {
        // Trigger container creation which starts async loading
        _ = container
    }
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Save error: \(error)")
            }
        }
    }
    
    func backgroundContext() -> NSManagedObjectContext {
        return container.newBackgroundContext()
    }
    
    private init() {
        // Start async initialization immediately
        initializeAsync()
    }
}