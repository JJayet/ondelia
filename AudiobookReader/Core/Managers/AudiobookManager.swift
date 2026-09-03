import Foundation
import SwiftData
import UIKit

class AudiobookManager: ObservableObject, AudiobookManagerProtocol {
    static let shared = AudiobookManager()
    let swiftDataController: SwiftDataController
    
    @Published var audiobooks: [AudiobookModel] = []
    @Published var isImporting = false
    @Published var importQueueTotal: Int = 0
    @Published var importQueueCompleted: Int = 0
    @Published var currentImportFileName: String? = nil
    @Published var isLoadingLibrary = false
    @Published var audiobookNeedingCover: AudiobookModel?
    
    var pendingImports: [(urls: [URL], completion: (() -> Void)?)] = []

    init(swiftDataController: SwiftDataController = .shared) {
        self.swiftDataController = swiftDataController
    }

    func getBookmarks(for audiobook: AudiobookModel) -> [BookmarkModel] {
        return audiobook.bookmarks
    }
    
    func markAsFinished(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
    }
    
    func resetProgress(for audiobook: AudiobookModel) {
        audiobook.currentPosition = 0
    }
    
    func updateProgress(for audiobook: AudiobookModel, currentTime: TimeInterval) {
        audiobook.currentPosition = currentTime
        audiobook.lastPlayed = Date()
        
        // Mark as finished if within 30 seconds of the end
        if audiobook.duration > 0 && (audiobook.duration - currentTime) <= 30 {
            audiobook.isFinished = true
        }
        
        swiftDataController.save()
    }
    
    @MainActor
    func createBookmark(for audiobook: AudiobookModel, at timestamp: TimeInterval, title: String, note: String? = nil) {
        let context = swiftDataController.context
        let bookmark = BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
        
        bookmark.audiobook = audiobook
        context.insert(bookmark)
        
        swiftDataController.save()
    }
    
    @MainActor
    func deleteBookmark(_ bookmark: BookmarkModel) {
        let context = swiftDataController.context
        context.delete(bookmark)
        swiftDataController.save()
    }

    // MARK: - Cover Image Management
    @MainActor
    func updateCoverImage(for audiobook: AudiobookModel, with image: UIImage) {
        audiobook.coverImageData = image.jpegData(compressionQuality: 0.8)
        swiftDataController.save()
        fetchAudiobooks()
        
        // Clear the needing cover flag if this was the audiobook that needed it
        if audiobookNeedingCover?.persistentModelID == audiobook.persistentModelID {
            audiobookNeedingCover = nil
        }
    }

    // MARK: - Progress Management (duplicate removed - the real implementation is earlier)
    
    // MARK: - Bookmark Management
    @MainActor
    func createBookmarkLegacy(for audiobook: AudiobookModel, at timestamp: TimeInterval, title: String, note: String? = nil) {
        // This is a duplicate - the real createBookmark using SwiftData is earlier in the file
        let context = swiftDataController.context
        let bookmark = BookmarkModel(
            title: title,
            note: note,
            timestamp: timestamp,
            dateCreated: Date()
        )
        bookmark.audiobook = audiobook
        context.insert(bookmark)
        
        swiftDataController.save()
    }
    
    // Legacy deleteBookmarkOld function removed - using SwiftData deleteBookmark instead
    
    // MARK: - Library Management
    @MainActor
    func deleteAudiobook(_ audiobook: AudiobookModel) {
        // Delete physical file
        if let filePath = audiobook.fileURL, !filePath.isEmpty {
            let fileURL = URL(fileURLWithPath: filePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from Core Data
        swiftDataController.context.delete(audiobook)
        swiftDataController.save()
        fetchAudiobooks()
    }
    
    @MainActor
    func renameAudiobook(_ audiobook: AudiobookModel, newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        audiobook.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        swiftDataController.save()
        fetchAudiobooks()
        
        print("✏️ AudiobookManager: Renamed audiobook to: \(newTitle)")
    }
    
    @MainActor
    func markAsRead(_ audiobook: AudiobookModel) {
        audiobook.isFinished = true
        audiobook.currentPosition = audiobook.duration // Set to end
        swiftDataController.save()
        fetchAudiobooks()
        
        print("✅ AudiobookManager: Marked audiobook as finished: \(audiobook.title ?? "Unknown")")
    }
    
    @MainActor
    func markAsUnread(_ audiobook: AudiobookModel) {
        audiobook.isFinished = false
        swiftDataController.save()
        fetchAudiobooks()
        
        print("🔄 AudiobookManager: Marked audiobook as unfinished: \(audiobook.title ?? "Unknown")")
    }
    
    func searchAudiobooks(query: String) -> [AudiobookModel] {
        guard !query.isEmpty else { return audiobooks }
        
        return audiobooks.filter { audiobook in
            let title = audiobook.title?.lowercased() ?? ""
            let author = audiobook.author?.lowercased() ?? ""
            let searchQuery = query.lowercased()
            
            return title.contains(searchQuery) || author.contains(searchQuery)
        }
    }
}
