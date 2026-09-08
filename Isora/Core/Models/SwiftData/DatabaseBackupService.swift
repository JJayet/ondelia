import Foundation
import SQLite3
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

    /// Writes a consistent copy of the store, verifies it opens, and prunes old ones.
    @discardableResult
    static func backUp(storeURL: URL, now: Date = Date()) -> URL? {
        let fileManager = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let destination = backupsDirectory.appendingPathComponent(stamp, isDirectory: true)

        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let copy = destination.appendingPathComponent(storeURL.lastPathComponent)
            guard vacuum(storeURL, into: copy), validate(copy) else {
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

    // MARK: - Restore

    /// What is on disk, newest first. The folder name is the timestamp it was written at.
    static func availableBackups() -> [(url: URL, date: Date)] {
        let formatter = ISO8601DateFormatter()
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return folders.compactMap { folder -> (url: URL, date: Date)? in
            // `backUp` dashed the time separators out of an ISO-8601 stamp so it could be a
            // folder name; only that part is put back.
            let name = folder.lastPathComponent
            guard let t = name.firstIndex(of: "T") else { return nil }
            let stamp = name[..<t] + name[t...].replacingOccurrences(of: "-", with: ":")
            guard let date = formatter.date(from: String(stamp)) else { return nil }
            return (folder, date)
        }
        .sorted { $0.date > $1.date }
    }

    /// Puts a backup back in place of the live store.
    ///
    /// The container is already open on the old file, so nothing here can hand the app a
    /// working store: the caller has to tell the user to relaunch.
    static func restore(_ backup: URL, storeURL: URL) throws {
        let fileManager = FileManager.default
        let source = backup.appendingPathComponent(storeURL.lastPathComponent)
        guard validate(source) else { throw RestoreError.unreadableBackup }

        // The journal files describe the store being replaced, so they go with it.
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? fileManager.removeItem(at: url)
        }
        try fileManager.copyItem(at: source, to: storeURL)
        Log.store.debug("✅ DatabaseBackupService: Restored \(backup.lastPathComponent)")
    }

    enum RestoreError: LocalizedError {
        case unreadableBackup

        var errorDescription: String? {
            NSLocalizedString("That backup could not be opened, so nothing was changed.",
                              comment: "Restore failure message")
        }
    }

    /// `VACUUM INTO` writes one self-contained file from inside SQLite, under a read
    /// transaction, so the copy is a point-in-time snapshot with the write-ahead log already
    /// folded in.
    ///
    /// Copying default.store, -wal and -shm as three separate files could not do that: they
    /// move at three different instants, and in practice the result was rejected on the very
    /// next launch with "file is not a database" — every backup discarded, which looked like
    /// the validation working rather than the copy being broken.
    private static func vacuum(_ storeURL: URL, into destination: URL) -> Bool {
        var database: OpaquePointer?
        // No SQLITE_OPEN_CREATE: a path that is not already a database must fail, not become
        // an empty one that then backs up perfectly.
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return false
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "VACUUM INTO ?", -1, &statement, nil) == SQLITE_OK else {
            Log.store.error("❌ DatabaseBackupService: \(String(cString: sqlite3_errmsg(database)))")
            return false
        }
        defer { sqlite3_finalize(statement) }

        // The C string stays alive across the step, so SQLite needs no copy of its own.
        return destination.path.withCString { path in
            guard sqlite3_bind_text(statement, 1, path, -1, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else {
                Log.store.error("❌ DatabaseBackupService: \(String(cString: sqlite3_errmsg(database)))")
                return false
            }
            return true
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
            configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)]
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
