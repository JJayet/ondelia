import CoreData
import Foundation

// MARK: - Changes made elsewhere
//
// CloudKit merges another device's edits straight into the store; `audiobooks` is a fetched
// array and would not notice. The store posts a remote-change notification for every such
// import (and for saves on other contexts, such as transcripts), so one debounced refetch covers
// them all.
extension AudiobookManager {
    func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRemoteRefetch() }
        }
    }

    private func scheduleRemoteRefetch() {
        remoteRefetchTask?.cancel()
        remoteRefetchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.swiftDataController.isLoaded else { return }
            self.fetchAudiobooks()
            ReadingStatistics.shared.reload()
            // A book deleted on another device may be the one loaded here. Checked on the model
            // itself, not by membership in `audiobooks`: a book the player holds from elsewhere
            // must not be torn down by a refetch.
            let audio = GlobalAudioManager.shared
            if let current = audio.currentAudiobook, current.isDeleted {
                audio.unload()
            }
        }
    }
}
