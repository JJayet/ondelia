import Foundation

extension AudiobookManager {
    /// Where iOS drops files sent with "Copy to Isora", AirDrop, or Finder file sharing.
    private static var inboxURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Imports anything waiting in the Inbox.
    ///
    /// Files can land there while the app is closed, so nothing tells the app they arrived —
    /// it has to look. Called on launch and whenever the app comes back to the foreground.
    @MainActor
    func importInboxFiles() {
        let inbox = Self.inboxURL
        // Called on every foreground, and a file picker or share sheet closing counts as one,
        // so the same files can still be sitting here from an import that has not finished.
        let waiting = ((try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).filter { !inboxHandedOff.contains($0.lastPathComponent) }
        guard !waiting.isEmpty else { return }

        Log.library.debug("📥 AudiobookManager: Found \(waiting.count) file(s) in the Inbox")
        for url in waiting { inboxHandedOff.insert(url.lastPathComponent) }

        handleImportRequest(urls: waiting) {
            // The copies in the library are the ones that count; the Inbox is a drop box, and
            // leaving files there imports them again on the next launch.
            Task { @MainActor [weak self] in
                for url in waiting {
                    try? FileManager.default.removeItem(at: url)
                    self?.inboxHandedOff.remove(url.lastPathComponent)
                }
            }
        }
    }
}
