import Foundation
import CoreData

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    
    @Published var isLoaded = false
    
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "AudiobookReader")
        
        container.loadPersistentStores { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    print("Core Data error: \(error), \(error.userInfo)")
                } else {
                    print("✅ Core Data loaded successfully")
                    self?.isLoaded = true
                }
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Optimize Core Data performance
        container.viewContext.stalenessInterval = 0.0
        
        return container
    }()
    
    var context: NSManagedObjectContext {
        container.viewContext
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
}