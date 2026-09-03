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
                        print("🖼️ FolderImporter: Found cover image: \(name).\(ext)")
                        return image
                    }
                }
            }
            
            // Fallback to any image file
            for url in contents {
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    if let image = UIImage(contentsOfFile: url.path) {
                        print("🖼️ FolderImporter: Using image: \(url.lastPathComponent)")
                        return image
                    }
                }
            }
        } catch {
            print("⚠️ FolderImporter: Could not search for cover image: \(error)")
        }
        
        return nil
    }
    
    static func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
