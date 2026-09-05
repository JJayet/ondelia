import Foundation

extension AudiobookModel {
    /// The folder every imported audiobook is copied into, and the root stored paths are relative to.
    static var libraryFolderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audiobooks")
    }

    /// The path segment that identifies a library location inside any app container.
    private static let libraryPathMarker = "/Documents/Audiobooks/"

    /// Where the audio actually is right now.
    ///
    /// `fileURL` holds a path relative to `libraryFolderURL`, because the app container's UUID
    /// changes on reinstall and on restore from an iOS backup — an absolute path written today
    /// names nothing after either. Absolute paths are still honoured for rows written before
    /// that change and for files that legitimately live outside the library.
    var resolvedFileURL: URL? {
        guard let fileURL, !fileURL.isEmpty else { return nil }
        guard !fileURL.hasPrefix("/") else { return URL(fileURLWithPath: fileURL) }
        return Self.libraryFolderURL.appendingPathComponent(fileURL)
    }

    /// What to store for a file just written into the library: relative when it is in the library,
    /// absolute otherwise.
    static func storedPath(for url: URL) -> String {
        libraryRelativePath(for: url.path) ?? url.path
    }

    /// The library-relative form of an absolute path, or nil when the path is not a library path.
    ///
    /// Matched on the `/Documents/Audiobooks/` segment rather than on the current container, so a
    /// path left behind by a *previous* container — the exact thing a restore produces — still
    /// converts into something that resolves today.
    ///
    /// The *first* match is the container's own library folder; a later one is a real subfolder
    /// that happens to be named the same and has to stay in the relative path.
    static func libraryRelativePath(for storedPath: String) -> String? {
        guard storedPath.hasPrefix("/"),
              let marker = storedPath.range(of: libraryPathMarker)
        else { return nil }
        let relative = String(storedPath[marker.upperBound...])
        return relative.isEmpty ? nil : relative
    }

    /// Rewrites a stale absolute library path in place. Returns true when the row changed.
    @discardableResult
    func migrateToRelativePath() -> Bool {
        guard let fileURL, let relative = Self.libraryRelativePath(for: fileURL) else { return false }
        self.fileURL = relative
        return true
    }
}
