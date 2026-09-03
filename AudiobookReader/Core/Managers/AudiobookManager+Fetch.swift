import Foundation
import SwiftData
import UIKit

extension AudiobookManager {
    // MARK: - Fetch Operations
    @MainActor
    func fetchAudiobooks() {
        // Prevent multiple concurrent fetch operations
        guard !isLoadingLibrary else { return }
        isLoadingLibrary = true
        // In previews or very early startup, SwiftData might not be ready yet.
        // Avoid touching the container until it's initialized to prevent fatalError.
        if !swiftDataController.isLoaded {
            if ProcessInfo.isPreview {
                // Provide preview data so Library previews are not empty
                self.audiobooks = [
                    PreviewContent.audiobook(title: "Dune", author: "Frank Herbert"),
                    PreviewContent.audiobook(title: "The Hobbit", author: "J.R.R. Tolkien"),
                    PreviewContent.audiobookLong()
                ]
            }
            // Defer real fetch until the container finishes loading,
            // then process any pending imports as part of that fetch.
            isLoadingLibrary = false
            Task { @MainActor in
                // Poll briefly until SwiftData finishes loading
                while !self.swiftDataController.isLoaded {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                self.fetchAudiobooks()
            }
            return
        }
        let context = swiftDataController.context
            let descriptor = FetchDescriptor<AudiobookModel>(
                sortBy: [
                    SortDescriptor(\.lastPlayed, order: .reverse),
                    SortDescriptor(\.dateAdded, order: .reverse)
                ]
            )
        do {
            let fetched = try context.fetch(descriptor)
            var valid: [AudiobookModel] = []
            var toDelete: [AudiobookModel] = []
            for book in fetched {
                if validateAudiobookFile(book) { valid.append(book) } else { toDelete.append(book) }
            }
            self.audiobooks = valid
            self.isLoadingLibrary = false
            self.processPendingImports()
            if !toDelete.isEmpty {
                for b in toDelete { context.delete(b) }
                do { try context.save() } catch {
                    print("❌ AudiobookManager: Failed to save after cleanup: \(error)")
                }
            }
        } catch {
            print("❌ AudiobookManager: Failed to fetch audiobooks: \(error)")
            self.isLoadingLibrary = false
        }
    }
    
    private func validateAudiobookFile(_ audiobook: AudiobookModel) -> Bool {
        guard let filePath = audiobook.fileURL, !filePath.isEmpty else {
            print("⚠️ AudiobookManager: No file path for audiobook '\(audiobook.title ?? "Unknown")'")
            return false
        }
        
        let fileExists = FileManager.default.fileExists(atPath: filePath)
        if !fileExists {
            print("⚠️ AudiobookManager: File does not exist at path: \(filePath)")
        }
        
        return fileExists
    }
}
