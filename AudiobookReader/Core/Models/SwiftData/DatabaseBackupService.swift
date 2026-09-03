import Foundation
import SwiftData

/// Keeps a couple of recent copies of the SwiftData store.
///
/// Progress, bookmarks and chapter data live only in that one file. A store that fails to open
/// after an OS or schema change takes the whole library with it, and nothing else in the app
/// can rebuild it — the audio files carry no progress.
enum DatabaseBackupService {
    private static let lastBackupKey = "lastDatabaseBackup"
    private static let interval: TimeInterval = 24 * 60 * 60
    private static let keep = 2

    static var backupsDirectory: URL {
        // Application Support, not Documents: file sharing exposes Documents to the Files app,
        // and a backup a user can delete by accident is not a backup.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DatabaseBackups", isDirectory: true)
    }

    /// Copies the store at most once a day. Never throws: a failed backup must not stop the app.
    static func backupIfDue(container: ModelContainer, now: Date = Date()) {
        let last = UserDefaults.standard.object(forKey: lastBackupKey) as? Date
        guard now.timeIntervalSince(last ?? .distantPast) >= interval else { return }
        guard let storeURL = container.configurations.first?.url else { return }
        guard backUp(storeURL: storeURL, now: now) != nil else { return }
        UserDefaults.standard.set(now, forKey: lastBackupKey)
    }

    /// Copies the store and its write-ahead log, verifies the copy opens, and prunes old ones.
    @discardableResult
    static func backUp(storeURL: URL, now: Date = Date()) -> URL? {
        let fileManager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = backupsDirectory.appendingPathComponent(stamp, isDirectory: true)

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            // The -wal and -shm siblings hold writes not yet folded into the store; a copy
            // without them can be missing the most recent listening entirely.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
            }
            guard validate(destination.appendingPathComponent(storeURL.lastPathComponent)) else {
                try? fileManager.removeItem(at: destination)
                Log.store.error("❌ DatabaseBackupService: Backup did not open, discarded")
                return nil
            }
            prune()
            Log.store.debug("✅ DatabaseBackupService: Backed up to \(destination.lastPathComponent)")
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            Log.store.error("❌ DatabaseBackupService: Backup failed: \(error)")
            return nil
        }
    }

    /// A copy that cannot be opened is worse than no copy, because it looks like protection.
    private static func validate(_ storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }
        let schema = Schema([
            AudiobookModel.self,
            BookmarkModel.self,
            ChapterModel.self,
            ChapterTranscriptionModel.self
        ])
        return (try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )) != nil
    }

    private static func prune() {
        let fileManager = FileManager.default
        let existing = (try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let stale = existing
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(keep)
        for url in stale {
            try? fileManager.removeItem(at: url)
        }
    }
}
