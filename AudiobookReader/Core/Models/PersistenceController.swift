import Foundation
import CoreData

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "AudiobookReader")
        
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
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