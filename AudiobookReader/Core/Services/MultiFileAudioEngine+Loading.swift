import Foundation
import AVFoundation
import MediaPlayer

extension MultiFileAudioEngine {
    // MARK: - Load Multi-File Audiobook
    func loadMultiFileAudiobook(_ audiobook: AudiobookModel) {
        print("🎵 MultiFileAudioEngine: Loading multi-file audiobook: \(audiobook.title ?? "Unknown")")
        
        // Setup audio session on first load; flag is only set on success so failures retry
        if !hasSetupAudioSession {
            setupAudioSession()
        }

        cleanup()
        
        self.audiobook = audiobook
        
        // Check if this is a folder-based audiobook
        guard let folderPath = audiobook.fileURL,
              FileManager.default.fileExists(atPath: folderPath) else {
            print("❌ MultiFileAudioEngine: Folder path not found: \(audiobook.fileURL ?? "nil")")
            return
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("📄 MultiFileAudioEngine: Single file detected, using regular audio engine")
            loadSingleFile(audiobook)
            return
        }
        
        // Load chapters and create players
        loadChaptersFromFolder(folderPath: folderPath, audiobook: audiobook)
    }
    
    private func loadSingleFile(_ audiobook: AudiobookModel) {
        guard let filePath = audiobook.fileURL else { return }
        let fileURL = URL(fileURLWithPath: filePath)
        
        let asset = AVURLAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        players = [0: player]
        playerItems = [0: playerItem]
        currentPlayerIndex = 0
        duration = audiobook.duration
        
        setupTimeObserver()
        setupNowPlayingInfo(for: audiobook)
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        hasAddedObservers.insert(playerItem)
        
        print("✅ MultiFileAudioEngine: Single file loaded successfully")
    }
    
    private func loadChaptersFromFolder(folderPath: String, audiobook: AudiobookModel) {
        let folderURL = URL(fileURLWithPath: folderPath)
        self.folderURL = folderURL

        // Get chapters from SwiftData, sorted by chapter number
        chapters = audiobook.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        
        guard !chapters.isEmpty else {
            print("❌ MultiFileAudioEngine: No chapters found")
            return
        }
        
        // Load manifest file to get file names (back to sync version for now)
        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
        if let manifestData = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let chaptersData = manifest["chapters"] as? [[String: Any]] {
            
            // Store file names for lazy loading
            chapterFiles.removeAll()
            chapterFiles.reserveCapacity(chaptersData.count)
            var totalDuration: TimeInterval = 0
            
            // Pre-validate all files in batch to avoid repeated file system calls
            var validChapterFiles: [(fileName: String, duration: TimeInterval)] = []
            validChapterFiles.reserveCapacity(chaptersData.count)
            
            for chapterData in chaptersData {
                guard let fileName = chapterData["fileName"] as? String else { continue }
                
                let fileURL = folderURL.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    print("⚠️ MultiFileAudioEngine: Chapter file not found: \(fileName)")
                    continue
                }
                
                let chapterDuration = chapterData["duration"] as? TimeInterval ?? 0
                validChapterFiles.append((fileName: fileName, duration: chapterDuration))
                totalDuration += chapterDuration
            }
            
            // Now populate the arrays with validated data
            chapterFiles = validChapterFiles.map(\.fileName)
            duration = totalDuration
            
            print("✅ MultiFileAudioEngine: Validated \(chapterFiles.count) chapter files")
        } else {
            print("⚠️ MultiFileAudioEngine: No manifest found, trying to load files directly")
            loadChaptersDirectly(folderPath: folderPath, audiobook: audiobook)
            return
        }
        
        currentPlayerIndex = 0
        
        // Find the correct chapter index based on current position
        if audiobook.currentPosition > 0 {
            currentChapterIndex = findChapterIndex(for: audiobook.currentPosition)
            currentPlayerIndex = currentChapterIndex
        }
        
        // Only load the current chapter initially (lazy loading)
        loadChapterPlayer(currentPlayerIndex)
        setupTimeObserver()
        
        // Setup now playing info asynchronously
        DispatchQueue.global(qos: .utility).async {
            self.setupNowPlayingInfo(for: audiobook)
        }
        
        print("✅ MultiFileAudioEngine: Multi-file audiobook initialized successfully")
        print("   Total duration: \(formatTime(duration))")
        print("   Chapters: \(chapterFiles.count)")
        print("   Starting chapter: \(currentChapterIndex + 1)")
    }
    
    private func loadChaptersDirectly(folderPath: String, audiobook: AudiobookModel) {
        // Fallback method to load chapters directly from audio files
        let folderURL = URL(fileURLWithPath: folderPath)
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey])
            let audioExtensions = ["mp3", "m4a", "m4b", "aac", "wav", "flac"]
            let audioFiles = contents.filter { url in
                audioExtensions.contains(url.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            for (index, fileURL) in audioFiles.enumerated() {
                let asset = AVURLAsset(url: fileURL)
                let playerItem = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: playerItem)
                
                players[index] = player
                playerItems[index] = playerItem
                
                playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
                hasAddedObservers.insert(playerItem)
                
                print("📖 MultiFileAudioEngine: Loaded file \(index + 1): \(fileURL.lastPathComponent)")
            }
            
            currentPlayerIndex = 0
            duration = audiobook.duration
            
            setupTimeObserver()
            
            // Setup now playing info asynchronously
            DispatchQueue.global(qos: .utility).async {
                self.setupNowPlayingInfo(for: audiobook)
            }
            
        } catch {
            print("❌ MultiFileAudioEngine: Failed to load chapter files directly: \(error)")
        }
    }
    
    // MARK: - Lazy Loading
    func loadChapterPlayer(_ chapterIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < chapterFiles.count,
              players[chapterIndex] == nil,
              let folderURL = folderURL else { return }
        
        let fileName = chapterFiles[chapterIndex]
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        let asset = AVURLAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        players[chapterIndex] = player
        playerItems[chapterIndex] = playerItem
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        hasAddedObservers.insert(playerItem)
        
        print("🔄 MultiFileAudioEngine: Lazy loaded chapter \(chapterIndex + 1): \(fileName)")
    }
    
    func preloadAdjacentChapters() {
        // Preload previous chapter
        if currentPlayerIndex > 0 {
            loadChapterPlayer(currentPlayerIndex - 1)
        }
        
        // Preload next chapter
        if currentPlayerIndex < chapterFiles.count - 1 {
            loadChapterPlayer(currentPlayerIndex + 1)
        }
    }
    
    func unloadDistantChapters() {
        // Unload chapters that are more than 2 positions away
        let indicesToUnload = players.keys.filter { index in
            abs(index - currentPlayerIndex) > 2
        }
        
        for index in indicesToUnload {
            unloadChapterPlayer(index)
        }
    }
    
    private func unloadChapterPlayer(_ chapterIndex: Int) {
        // This method is called from playerQueue, so it's already thread-safe
        guard let player = players[chapterIndex],
              let playerItem = playerItems[chapterIndex] else { return }
        
        // Remove observer
        if hasAddedObservers.contains(playerItem) {
            playerItem.removeObserver(self, forKeyPath: "status")
            hasAddedObservers.remove(playerItem)
        }
        
        // Remove time observer if this is the current player
        if chapterIndex == currentPlayerIndex, let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Clean up
        players.removeValue(forKey: chapterIndex)
        playerItems.removeValue(forKey: chapterIndex)
        
        print("🗑️ MultiFileAudioEngine: Unloaded distant chapter \(chapterIndex + 1)")
    }
}
