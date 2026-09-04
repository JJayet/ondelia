import Foundation
import UIKit

extension FolderImporter {
    // MARK: - Helper Methods
    static func extractTitle(from folderName: String) -> String {
        // Try to extract title from folder name like "Author - Title"
        if let dashRange = folderName.range(of: " - ") {
            return String(folderName[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback to folder name
        return folderName
    }
    
    static func extractAuthor(from folderName: String) -> String? {
        // Try to extract author from folder name like "Author - Title"
        if let dashRange = folderName.range(of: " - ") {
            return String(folderName[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    static func generateChapterTitle(from fileName: String, index: Int) -> String {
        // Remove file extension
        let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        
        // If filename contains meaningful text, use it
        if nameWithoutExtension.count > 10 && !nameWithoutExtension.allSatisfy({ $0.isNumber || $0 == "_" }) {
            return nameWithoutExtension.replacingOccurrences(of: "_", with: " ")
        }
        
        // Otherwise, use generic chapter naming
        return "Chapter \(index)"
    }
    
    static let audioFileExtensions = ["mp3", "m4a", "m4b", "aac", "wav", "flac", "opus", "ogg", "aiff", "aif"]

    static func isAudioFile(_ url: URL) -> Bool {
        audioFileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Audio files anywhere under `folderURL`, sorted the way Finder would sort them.
    /// Recursive, because a book is just as often shipped as `Book/Disc 1/01.mp3`
    /// as it is as a flat folder.
    static func audioFiles(in folderURL: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        let files = (enumerator?.allObjects as? [URL] ?? []).filter(isAudioFile)
        return files.sorted {
            relativePath(of: $0, in: folderURL)
                .localizedStandardCompare(relativePath(of: $1, in: folderURL)) == .orderedAscending
        }
    }

    /// The path of `url` relative to `folderURL`, so a chapter in a subfolder keeps its subfolder.
    /// Falls back to the file name when `url` is not under `folderURL` (hand-picked selections).
    static func relativePath(of url: URL, in folderURL: URL) -> String {
        let root = folderURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }

    static func findCoverImage(in folderURL: URL) async -> UIImage? {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
        let commonNames = ["cover", "folder", "albumart", "front"]
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey])
            
            // Look for common cover image names first
            for name in commonNames {
                for ext in imageExtensions {
                    let imageURL = folderURL.appendingPathComponent("\(name).\(ext)")
                    if contents.contains(imageURL), let image = UIImage(contentsOfFile: imageURL.path) {
                        Log.library.debug("🖼️ FolderImporter: Found cover image: \(name).\(ext)")
                        return image
                    }
                }
            }
            
            // Fallback to any image file
            for url in contents {
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    if let image = UIImage(contentsOfFile: url.path) {
                        Log.library.debug("🖼️ FolderImporter: Using image: \(url.lastPathComponent)")
                        return image
                    }
                }
            }
        } catch {
            Log.library.warning("⚠️ FolderImporter: Could not search for cover image: \(error)")
        }
        
        return nil
    }
    
}
