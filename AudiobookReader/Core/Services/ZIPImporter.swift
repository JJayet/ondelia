import Foundation
import Compression

class ZIPImporter {
    
    static func importZIPFile(from zipURL: URL) async -> URL? {
        print("📦 ZIPImporter: Starting ZIP import from: \(zipURL.lastPathComponent)")
        
        // Create temporary extraction directory
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudiobookExtraction")
            .appendingPathComponent(UUID().uuidString)
        
        guard createDirectory(at: tempDirectory) else {
            print("❌ ZIPImporter: Failed to create temporary directory")
            return nil
        }
        
        // Extract ZIP file
        guard await extractZIP(from: zipURL, to: tempDirectory) else {
            print("❌ ZIPImporter: Failed to extract ZIP file")
            cleanupDirectory(at: tempDirectory)
            return nil
        }
        
        // Validate audiobook content
        guard let audiobookFolder = await validateAudiobookContent(in: tempDirectory) else {
            print("❌ ZIPImporter: No valid audiobook content found")
            cleanupDirectory(at: tempDirectory)
            return nil
        }
        
        print("✅ ZIPImporter: Successfully validated audiobook content")
        return audiobookFolder
    }
    
    private static func createDirectory(at url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            print("📁 ZIPImporter: Created temporary directory: \(url.path)")
            return true
        } catch {
            print("❌ ZIPImporter: Failed to create directory: \(error)")
            return false
        }
    }
    
    private static func extractZIP(from zipURL: URL, to destinationURL: URL) async -> Bool {
        // For now, return a placeholder that indicates ZIP import is not available
        // In a real implementation, you would use a proper ZIP library
        print("⚠️ ZIPImporter: ZIP extraction not implemented - would extract \(zipURL.lastPathComponent) to \(destinationURL.path)")
        return false
    }
    
    private static func validateAudiobookContent(in directory: URL) async -> URL? {
        let fileManager = FileManager.default
        let audioExtensions = ["mp3", "m4a", "m4b", "aac", "wav", "flac"]
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
            
            // Look for audio files directly in extracted directory
            var audioFiles = contents.filter { url in
                audioExtensions.contains(url.pathExtension.lowercased())
            }
            
            // If no audio files at root level, look one level deeper
            if audioFiles.isEmpty {
                let subdirectories = contents.filter { url in
                    var isDirectory: ObjCBool = false
                    fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    return isDirectory.boolValue
                }
                
                for subdirectory in subdirectories {
                    let subContents = try fileManager.contentsOfDirectory(at: subdirectory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
                    let subAudioFiles = subContents.filter { url in
                        audioExtensions.contains(url.pathExtension.lowercased())
                    }
                    
                    if subAudioFiles.count > audioFiles.count {
                        audioFiles = subAudioFiles
                        // Return the subdirectory with the most audio files
                        return subdirectory
                    }
                }
            }
            
            // Validate audiobook criteria
            guard !audioFiles.isEmpty else {
                print("❌ ZIPImporter: No audio files found")
                return nil
            }
            
            // Check total size and duration requirements
            var totalSize: Int64 = 0
            var validAudioFiles = 0
            
            for audioFile in audioFiles {
                let attributes = try fileManager.attributesOfItem(atPath: audioFile.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                // Skip very small files (likely not audiobook content)
                if fileSize > 1_000_000 { // 1MB minimum
                    totalSize += fileSize
                    validAudioFiles += 1
                }
            }
            
            guard validAudioFiles >= 1 && totalSize > 10_000_000 else { // 10MB minimum total
                print("❌ ZIPImporter: Insufficient valid audio content. Files: \(validAudioFiles), Size: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                return nil
            }
            
            print("✅ ZIPImporter: Valid audiobook found - \(validAudioFiles) files, \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
            
            // Return the directory containing the audio files
            return audioFiles.first?.deletingLastPathComponent() ?? directory
            
        } catch {
            print("❌ ZIPImporter: Error validating content: \(error)")
            return nil
        }
    }
    
    static func cleanupDirectory(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("🗑️ ZIPImporter: Cleaned up temporary directory")
        } catch {
            print("⚠️ ZIPImporter: Failed to cleanup temporary directory: \(error)")
        }
    }
}