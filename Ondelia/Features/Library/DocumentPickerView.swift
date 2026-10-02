import SwiftUI
import UniformTypeIdentifiers

/// The document picker, driven directly rather than through `.fileImporter`.
///
/// Two `.fileImporter` modifiers on one view do not coexist — the later one shadows the earlier —
/// and one whose content types come from state reads whatever the last body evaluation captured.
/// Owning the controller sidesteps both.
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    /// No `.folder`: with folders allowed the browser treats a tap on one as "go inside", so a
    /// folder can never actually be chosen. A folder still imports fine when it arrives some
    /// other way — a ZIP, or "Open in" — see `importAudiobookFolder`.
    private var contentTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .zip]
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let m4b = UTType(filenameExtension: "m4b") { types.append(m4b) }
        return types
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        picker.directoryURL = Self.lastFolder
        return picker
    }

    /// Where the last pick came from, so the next one opens there. Without it the picker opens
    /// in the app's own Documents folder, which file sharing puts in Files, and which only holds
    /// books that are already imported.
    private static let lastFolderKey = "import.lastPickerFolder"

    static var lastFolder: URL? {
        UserDefaults.standard.string(forKey: lastFolderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Remembers the folder of `urls`, unless it is inside the app's own container: that is the
    /// location this exists to steer away from.
    static func rememberFolder(of urls: [URL]) {
        guard let folder = urls.first?.deletingLastPathComponent().standardizedFileURL else { return }
        let container = URL.homeDirectory.standardizedFileURL.path + "/"
        guard !folder.path.hasPrefix(container) else { return }
        UserDefaults.standard.set(folder.path, forKey: lastFolderKey)
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            DocumentPickerView.rememberFolder(of: urls)
            onPick(urls)
        }
    }
}
