import Foundation

// MARK: - CUE File Data Models
struct CUEFile {
    let fileName: String
    let fileType: String
    let tracks: [CUETrack]
    let title: String?
    let performer: String?
}

struct CUETrack {
    let number: Int
    let title: String
    let startTime: TimeInterval
    let type: String
}

// MARK: - CUE File Parser
enum CUEParser {
    
    static func parseCUEFile(at url: URL) -> CUEFile? {
        Log.library.debug("🎵 CUEParser: Starting to parse CUE file: \(url.lastPathComponent)")
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            Log.library.error("❌ CUEParser: Failed to read CUE file content")
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var fileName: String = ""
        var fileType: String = ""
        var title: String?
        var performer: String?
        var tracks: [CUETrack] = []
        var currentTrack: (number: Int, title: String, startTime: TimeInterval, type: String)?
        
        for line in lines {
            // Parse FILE line
            if line.hasPrefix("FILE") {
                let components = parseQuotedLine(line)
                if components.count >= 2 {
                    fileName = components[1]
                    fileType = components.count > 2 ? components[2] : "AUDIO"
                }
            }
            // Parse global TITLE
            else if line.hasPrefix("TITLE") && currentTrack == nil {
                title = extractQuotedValue(from: line)
            }
            // Parse global PERFORMER
            else if line.hasPrefix("PERFORMER") && currentTrack == nil {
                performer = extractQuotedValue(from: line)
            }
            // Parse TRACK line
            else if line.hasPrefix("TRACK") {
                // Save previous track if exists
                if let track = currentTrack {
                    tracks.append(CUETrack(
                        number: track.number,
                        title: track.title,
                        startTime: track.startTime,
                        type: track.type
                    ))
                }
                
                let components = line.components(separatedBy: .whitespaces)
                if components.count >= 3 {
                    let trackNumber = Int(components[1]) ?? 0
                    let trackType = components[2]
                    currentTrack = (number: trackNumber, title: "Track \(trackNumber)", startTime: 0, type: trackType)
                }
            }
            // Parse track TITLE
            else if line.hasPrefix("TITLE"), var track = currentTrack {
                if let trackTitle = extractQuotedValue(from: line) {
                    track.title = trackTitle
                    currentTrack = track
                }
            }
            // Parse INDEX line (track start time)
            else if line.hasPrefix("INDEX"), var track = currentTrack {
                let components = line.components(separatedBy: .whitespaces)
                if components.count >= 3 && components[1] == "01" {
                    let timeString = components[2]
                    track.startTime = parseTimeString(timeString)
                    currentTrack = track
                }
            }
        }
        
        // Add the last track
        if let track = currentTrack {
            tracks.append(CUETrack(
                number: track.number,
                title: track.title,
                startTime: track.startTime,
                type: track.type
            ))
        }
        
        Log.library.debug("✅ CUEParser: Successfully parsed \(tracks.count) tracks from CUE file")
        
        return CUEFile(
            fileName: fileName,
            fileType: fileType,
            tracks: tracks,
            title: title,
            performer: performer
        )
    }
    
    // MARK: - Private Helper Methods
    
    private static func parseQuotedLine(_ line: String) -> [String] {
        var components: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let char = line[i]
            
            if char == "\"" {
                inQuotes.toggle()
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    components.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
            
            i = line.index(after: i)
        }
        
        if !current.isEmpty {
            components.append(current)
        }
        
        return components
    }
    
    private static func extractQuotedValue(from line: String) -> String? {
        let components = parseQuotedLine(line)
        return components.count > 1 ? components[1] : nil
    }
    
    private static func parseTimeString(_ timeString: String) -> TimeInterval {
        // Parse MM:SS:FF format (Minutes:Seconds:Frames where 75 frames = 1 second)
        let components = timeString.components(separatedBy: ":")
        guard components.count == 3 else {
            Log.library.warning("⚠️ CUEParser: Invalid time format: \(timeString)")
            return 0
        }
        
        // Doubles, not Ints: a malformed file's minutes times 60 must not overflow and trap.
        let minutes = TimeInterval(components[0]) ?? 0
        let seconds = TimeInterval(components[1]) ?? 0
        let frames = TimeInterval(components[2]) ?? 0
        
        // Convert to total seconds (75 frames = 1 second in CD audio)
        let totalSeconds = minutes * 60 + seconds + frames / 75.0
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return 0 }
        
        return totalSeconds
    }
    
    // MARK: - Utility Methods
    
    static func findCUEFiles(in directoryURL: URL) -> [URL] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            let cueFiles = contents.filter { $0.pathExtension.lowercased() == "cue" }
            Log.library.debug("🔍 CUEParser: Found \(cueFiles.count) CUE files in directory")
            
            return cueFiles
        } catch {
            Log.library.error("❌ CUEParser: Failed to scan directory for CUE files: \(error)")
            return []
        }
    }
    
    static func matchCUEWithAudioFile(cueFile: CUEFile, in directoryURL: URL) -> URL? {
        // Look for the audio file referenced in the CUE file
        let referencedFileName = cueFile.fileName
        let referencedFileURL = directoryURL.appendingPathComponent(referencedFileName)
        
        if FileManager.default.fileExists(atPath: referencedFileURL.path) {
            Log.library.debug("✅ CUEParser: Found referenced audio file: \(referencedFileName)")
            return referencedFileURL
        }
        
        // If not found, look for similar files (case insensitive, different extensions)
        let baseName = (referencedFileName as NSString).deletingPathExtension
        let audioExtensions = ["m4b", "m4a", "mp3", "aac", "wav", "flac"]
        
        for ext in audioExtensions {
            let candidateURL = directoryURL.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                Log.library.debug("✅ CUEParser: Found matching audio file: \(candidateURL.lastPathComponent)")
                return candidateURL
            }
        }
        
        Log.library.warning("⚠️ CUEParser: No matching audio file found for CUE: \(referencedFileName)")
        return nil
    }
    
}

// MARK: - CUE Integration Extensions
extension FolderChapter {
    init(from cueTrack: CUETrack, endTime: TimeInterval, fileName: String) {
        self.init(
            title: cueTrack.title,
            fileName: fileName,
            duration: endTime - cueTrack.startTime,
            startTimeInBook: cueTrack.startTime,
            chapterNumber: cueTrack.number,
            fileSize: 0
        )
    }
}