import Foundation
import ZIPFoundation

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
        print("📦 ZIPImporter: Extracting ZIP file \(zipURL.lastPathComponent) to \(destinationURL.path)")
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Create the destination directory if it doesn't exist
                    if !FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
                    }
                    
                    // Open the ZIP archive
                    let archive: Archive
                    do {
                        archive = try Archive(url: zipURL, accessMode: .read)
                    } catch {
                        print("❌ ZIPImporter: Failed to open ZIP archive: \(error)")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    print("📊 ZIPImporter: Starting ZIP extraction...")
                    
                    var extractedCount = 0
                    
                    // Extract all entries
                    for entry in archive {
                        let entryDestinationURL = destinationURL.appendingPathComponent(entry.path)
                        
                        // Ensure the directory structure exists
                        let entryDirectory = entryDestinationURL.deletingLastPathComponent()
                        if !FileManager.default.fileExists(atPath: entryDirectory.path) {
                            try FileManager.default.createDirectory(at: entryDirectory, withIntermediateDirectories: true, attributes: nil)
                        }
                        
                        // Skip if it's a directory entry
                        if entry.type == .directory {
                            continue
                        }
                        
                        // Extract the file
                        _ = try archive.extract(entry, to: entryDestinationURL)
                        extractedCount += 1
                        print("   ✅ Extracted: \(entry.path)")
                    }
                    
                    print("✅ ZIPImporter: Successfully extracted \(extractedCount) files")
                    continuation.resume(returning: true)
                    
                } catch {
                    print("❌ ZIPImporter: Failed to extract ZIP file: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private static func validateAudiobookContent(in directory: URL) async -> URL? {
        let fileManager = FileManager.default
        let audioExtensions = ["mp3", "m4a", "m4b", "aac", "wav", "flac"]
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
            
            var targetDirectory = directory
            var audioFiles: [URL] = []
            
            // Look for audio files directly in extracted directory
            audioFiles = contents.filter { url in
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
                        targetDirectory = subdirectory
                    }
                }
            }
            
            // Validate audiobook criteria
            guard !audioFiles.isEmpty else {
                print("❌ ZIPImporter: No audio files found")
                return nil
            }
            
            // Check for CUE files in the target directory
            let cueFiles = CUEParser.findCUEFiles(in: targetDirectory)
            if !cueFiles.isEmpty {
                print("🎵 ZIPImporter: Found \(cueFiles.count) CUE file(s) in extracted content")
                
                // If we have CUE files, validate that we can parse them and find associated audio
                for cueFileURL in cueFiles {
                    if let parsedCUE = CUEParser.parseCUEFile(at: cueFileURL) {
                        if let _ = CUEParser.matchCUEWithAudioFile(cueFile: parsedCUE, in: targetDirectory) {
                            print("✅ ZIPImporter: Valid CUE-based audiobook found")
                            return targetDirectory
                        }
                    }
                }
            }
            
            // Check total size and duration requirements for regular audio files
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
            
            return targetDirectory
            
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