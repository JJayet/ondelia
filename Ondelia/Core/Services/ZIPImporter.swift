import Foundation
import ZIPFoundation

enum ZIPImporter {
    static let maximumEntryCount = 10_000
    static let maximumEntrySize: UInt64 = 4 * 1_024 * 1_024 * 1_024
    static let maximumExpandedSize: UInt64 = 20 * 1_024 * 1_024 * 1_024
    static let maximumCompressionRatio: UInt64 = 200
    
    /// Synchronous on purpose: the only caller already runs off the main actor, so wrapping
    /// this in a continuation only bought an extra thread hop.
    static func importZIPFile(from zipURL: URL) -> (folder: URL, root: URL)? {
        Log.library.debug("📦 ZIPImporter: Starting ZIP import from: \(zipURL.lastPathComponent)")
        
        // Create temporary extraction directory
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudiobookExtraction")
            .appendingPathComponent(UUID().uuidString)
        
        guard createDirectory(at: tempDirectory) else {
            Log.library.error("❌ ZIPImporter: Failed to create temporary directory")
            return nil
        }
        
        // Extract ZIP file
        do {
            try extractZIP(from: zipURL, to: tempDirectory)
        } catch {
            Log.library.error("❌ ZIPImporter: Failed to extract ZIP file: \(error.localizedDescription)")
            cleanupDirectory(at: tempDirectory)
            return nil
        }
        
        // Validate audiobook content
        guard let audiobookFolder = validateAudiobookContent(in: tempDirectory) else {
            Log.library.error("❌ ZIPImporter: No valid audiobook content found")
            cleanupDirectory(at: tempDirectory)
            return nil
        }
        
        Log.library.debug("✅ ZIPImporter: Successfully validated audiobook content")
        // The extraction root travels with the folder: it is the only thing safe to delete
        // afterwards, and it is not derivable from the folder — an archive with audio at its
        // root makes the two the same directory.
        return (folder: audiobookFolder, root: tempDirectory)
    }
    
    private static func createDirectory(at url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            Log.library.debug("📁 ZIPImporter: Created temporary directory: \(url.path)")
            return true
        } catch {
            Log.library.error("❌ ZIPImporter: Failed to create directory: \(error)")
            return false
        }
    }
    
    private static func extractZIP(from zipURL: URL, to destinationURL: URL) throws {
        Log.library.debug("📦 ZIPImporter: Extracting ZIP file \(zipURL.lastPathComponent) to \(destinationURL.path)")

        // Create the destination directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        }

        let archive = try Archive(url: zipURL, accessMode: .read)

        Log.library.debug("📊 ZIPImporter: Starting ZIP extraction...")

        var extractedCount = 0
        var expandedSize: UInt64 = 0

        // Extract all entries
        for entry in archive {
            guard extractedCount < maximumEntryCount else {
                throw ZIPImportError.tooManyEntries
            }
            guard entry.type != .symlink else {
                throw ZIPImportError.symbolicLink(entry.path)
            }
            guard entry.uncompressedSize <= maximumEntrySize else {
                throw ZIPImportError.entryTooLarge(entry.path)
            }
            let (newExpandedSize, overflow) = expandedSize.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, newExpandedSize <= maximumExpandedSize else {
                throw ZIPImportError.archiveTooLarge
            }
            if entry.compressedSize == 0 {
                guard entry.uncompressedSize == 0 else {
                    throw ZIPImportError.suspiciousCompression(entry.path)
                }
            } else {
                guard entry.uncompressedSize / entry.compressedSize <= maximumCompressionRatio else {
                    throw ZIPImportError.suspiciousCompression(entry.path)
                }
            }

            let entryDestinationURL = try SafeImportPath.resolvedURL(
                for: entry.path,
                inside: destinationURL
            )
            expandedSize = newExpandedSize

            // Ensure the directory structure exists
            let entryDirectory = entryDestinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: entryDirectory.path) {
                try FileManager.default.createDirectory(at: entryDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            // Skip if it's a directory entry
            if entry.type == .directory {
                extractedCount += 1
                continue
            }

            // Extract the file
            _ = try archive.extract(entry, to: entryDestinationURL)
            extractedCount += 1
            Log.library.debug("   ✅ Extracted: \(entry.path)")
        }

        Log.library.debug("✅ ZIPImporter: Successfully extracted \(extractedCount) files")
    }
    
    static func validateAudiobookContent(in directory: URL) -> URL? {
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
                Log.library.error("❌ ZIPImporter: No audio files found")
                return nil
            }
            
            // Check for CUE files in the target directory
            let cueFiles = CUEParser.findCUEFiles(in: targetDirectory)
            if !cueFiles.isEmpty {
                Log.library.debug("🎵 ZIPImporter: Found \(cueFiles.count) CUE file(s) in extracted content")
                
                // If we have CUE files, validate that we can parse them and find associated audio
                for cueFileURL in cueFiles {
                    if let parsedCUE = CUEParser.parseCUEFile(at: cueFileURL) {
                        if let _ = CUEParser.matchCUEWithAudioFile(cueFile: parsedCUE, in: targetDirectory) {
                            Log.library.debug("✅ ZIPImporter: Valid CUE-based audiobook found")
                            return targetDirectory
                        }
                    }
                }
            }
            
            // Only empty files are refused. The 1 MB-per-file and 10 MB-total minimums this used
            // to apply rejected real books — a children's audiobook is one 8 MB m4b — while a
            // lone audio file picked from Files had no minimum at all.
            var totalSize: Int64 = 0
            var validAudioFiles = 0

            for audioFile in audioFiles {
                let attributes = try fileManager.attributesOfItem(atPath: audioFile.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                if fileSize > 0 {
                    totalSize += fileSize
                    validAudioFiles += 1
                }
            }

            guard validAudioFiles >= 1 else {
                Log.library.error("❌ ZIPImporter: Only empty audio files found")
                return nil
            }
            
            Log.library.debug("✅ ZIPImporter: Valid audiobook found - \(validAudioFiles) files, \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
            
            return targetDirectory
            
        } catch {
            Log.library.error("❌ ZIPImporter: Error validating content: \(error)")
            return nil
        }
    }
    
    static func cleanupDirectory(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Log.library.debug("🗑️ ZIPImporter: Cleaned up temporary directory")
        } catch {
            Log.library.warning("⚠️ ZIPImporter: Failed to cleanup temporary directory: \(error)")
        }
    }
}

private enum ZIPImportError: LocalizedError {
    case tooManyEntries
    case entryTooLarge(String)
    case archiveTooLarge
    case suspiciousCompression(String)
    case symbolicLink(String)

    var errorDescription: String? {
        switch self {
        case .tooManyEntries:
            return "The archive contains too many entries."
        case .entryTooLarge(let path):
            return "The archive entry is too large: \(path)"
        case .archiveTooLarge:
            return "The expanded archive is too large."
        case .suspiciousCompression(let path):
            return "The archive has a suspicious compression ratio: \(path)"
        case .symbolicLink(let path):
            return "Symbolic links are not allowed in audiobook archives: \(path)"
        }
    }
}
