import SwiftUI

/// What the library weighs on disk, book by book, with a way to drop the heavy ones.
struct StorageView: View {
    @Environment(\.dismiss) private var dismiss
    private let manager = AudiobookManager.shared
    @State private var report: StorageReport?
    @State private var pendingDelete: AudiobookModel?
    @State private var confirmingOrphanDelete = false

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    Section {
                        sizeRow(NSLocalizedString("Audio files", comment: "Storage row: every book's audio"), report.booksBytes)
                        if report.otherBytes > 0 {
                            sizeRow(NSLocalizedString("Other files", comment: "Storage row: library files no book uses"), report.otherBytes)
                        }
                    } header: {
                        Text(String(
                            format: NSLocalizedString("%@ used", comment: "Storage total header"),
                            report.totalBytes.formatted(.byteCount(style: .file))
                        ))
                    } footer: {
                        if report.otherBytes > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString(
                                    "Other files are in the library folder but belong to no book: an interrupted import, or a book deleted on another device.",
                                    comment: "Storage footer explaining orphan files"
                                ))
                                Button(NSLocalizedString("Delete other files", comment: "Remove library files no book uses"), role: .destructive) {
                                    confirmingOrphanDelete = true
                                }
                                .disabled(manager.isImporting)
                            }
                        }
                    }

                    Section(NSLocalizedString("By book", comment: "Storage section: per-book sizes")) {
                        ForEach(report.books) { entry in
                            sizeRow(entry.title, entry.bytes)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                                        pendingDelete = manager.audiobooks.first { $0.id == entry.id }
                                    }
                                    .tint(.red)
                                }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(NSLocalizedString("Storage", comment: "Storage view title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { withHapticFeedback { dismiss() } }
                }
            }
            .task { await refresh() }
            .alert(
                NSLocalizedString("Delete other files", comment: "Remove library files no book uses"),
                isPresented: $confirmingOrphanDelete
            ) {
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    for url in report?.orphans ?? [] {
                        try? FileManager.default.removeItem(at: url)
                    }
                    Task { await refresh() }
                }
            } message: {
                Text(String(
                    format: NSLocalizedString(
                        "%d files in the library folder that no book uses will be removed.",
                        comment: "Orphan cleanup confirmation"
                    ),
                    report?.orphans.count ?? 0
                ))
            }
            .alert(
                NSLocalizedString("Delete Audiobook", comment: "Delete confirmation alert title"),
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { audiobook in
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                    manager.deleteAudiobook(audiobook)
                    Task { await refresh() }
                }
            } message: { audiobook in
                Text(String(
                    format: NSLocalizedString(
                        "'%@', its progress and its bookmarks will be removed. This cannot be undone.",
                        comment: "Delete confirmation alert message"
                    ),
                    audiobook.title ?? AudiobookModel.unknownTitle
                ))
            }
        }
    }

    private func sizeRow(_ title: String, _ bytes: Int64) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            Text(bytes.formatted(.byteCount(style: .file)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func refresh() async {
        report = await StorageReport.build(for: manager.audiobooks)
    }
}

/// Sizes gathered off the main actor. Models are not `Sendable`, so the walk takes plain values.
struct StorageReport: Sendable {
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let title: String
        let bytes: Int64
    }

    /// Heaviest first.
    let books: [Entry]
    /// Top-level items in the library folder that no book points into.
    let orphans: [URL]
    let otherBytes: Int64

    var booksBytes: Int64 { books.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { booksBytes + otherBytes }

    @MainActor
    static func build(for audiobooks: [AudiobookModel]) async -> StorageReport {
        let inputs = audiobooks.map { ($0.id, $0.title ?? AudiobookModel.unknownTitle, $0.resolvedFileURL) }
        let libraryURL = AudiobookModel.libraryFolderURL
        return await Task.detached(priority: .userInitiated) {
            var entries: [Entry] = []
            for (id, title, url) in inputs {
                guard let url else { continue }
                entries.append(Entry(id: id, title: title, bytes: StorageUsage.bytes(at: url)))
            }
            entries.sort { $0.bytes > $1.bytes }
            let orphans = StorageUsage.orphans(in: libraryURL, referenced: inputs.compactMap(\.2))
            return StorageReport(
                books: entries,
                orphans: orphans,
                otherBytes: orphans.reduce(0) { $0 + StorageUsage.bytes(at: $1) }
            )
        }.value
    }
}

enum StorageUsage {
    /// Top-level items of `folder` that none of `referenced` sits in or under.
    nonisolated static func orphans(in folder: URL, referenced: [URL]) -> [URL] {
        let root = folder.standardizedFileURL.path
        // A book's first path component under the library is the item that belongs to it.
        let owned = Set(referenced.compactMap { url -> String? in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root + "/") else { return nil }
            return path.dropFirst(root.count + 1).split(separator: "/").first.map(String.init)
        })
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return items.filter { !owned.contains($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Bytes at a path: the file itself, or every file under a folder.
    nonisolated static func bytes(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.fileSize ?? 0) }
        guard let files = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
