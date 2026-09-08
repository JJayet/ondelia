import SwiftUI

/// What the library weighs on disk, book by book, with a way to drop the heavy ones.
struct StorageView: View {
    @Environment(\.dismiss) private var dismiss
    private let manager = AudiobookManager.shared
    @State private var report: StorageReport?
    @State private var pendingDelete: AudiobookModel?

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
                            Text(NSLocalizedString(
                                "Other files are in the library folder but belong to no book, usually left by an interrupted import.",
                                comment: "Storage footer explaining orphan files"
                            ))
                        }
                    }

                    Section(NSLocalizedString("By book", comment: "Storage section: per-book sizes")) {
                        ForEach(report.books) { entry in
                            sizeRow(entry.title, entry.bytes)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                                        pendingDelete = manager.audiobooks.first { $0.id == entry.id }
                                    }
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
    /// Everything under the library folder, whether or not a book points at it.
    let libraryBytes: Int64
    /// Bytes of the books that live inside the library folder, so `otherBytes` can be derived.
    let inLibraryBytes: Int64

    var booksBytes: Int64 { books.reduce(0) { $0 + $1.bytes } }
    var otherBytes: Int64 { max(libraryBytes - inLibraryBytes, 0) }
    var totalBytes: Int64 { booksBytes + otherBytes }

    @MainActor
    static func build(for audiobooks: [AudiobookModel]) async -> StorageReport {
        let inputs = audiobooks.map { ($0.id, $0.title ?? AudiobookModel.unknownTitle, $0.resolvedFileURL) }
        let libraryURL = AudiobookModel.libraryFolderURL
        return await Task.detached(priority: .userInitiated) {
            var entries: [Entry] = []
            var inLibrary: Int64 = 0
            for (id, title, url) in inputs {
                guard let url else { continue }
                let bytes = StorageUsage.bytes(at: url)
                entries.append(Entry(id: id, title: title, bytes: bytes))
                if url.path.hasPrefix(libraryURL.path) { inLibrary += bytes }
            }
            entries.sort { $0.bytes > $1.bytes }
            return StorageReport(
                books: entries,
                libraryBytes: StorageUsage.bytes(at: libraryURL),
                inLibraryBytes: inLibrary
            )
        }.value
    }
}

enum StorageUsage {
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
