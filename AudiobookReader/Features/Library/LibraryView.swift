import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var audiobookManager = AudiobookManager()
    @State private var showingFilePicker = false
    @State private var showingImagePicker = false
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    
    private var filteredAudiobooks: [Audiobook] {
        audiobookManager.searchAudiobooks(query: searchText)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                    // Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        
                        Text("No Audiobooks")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Import your first audiobook to get started")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Import Audiobook") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    // Library List
                    List {
                        if audiobookManager.isImporting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Importing audiobook...")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                        
                        ForEach(filteredAudiobooks, id: \.id) { audiobook in
                            NavigationLink(value: audiobook) {
                                AudiobookRowView(audiobook: audiobook)
                            }
                        }
                        .onDelete(perform: deleteAudiobooks)
                    }
                    .searchable(text: $searchText, prompt: "Search audiobooks...")
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Audiobook.self) { audiobook in
                PlayerView(audiobook: audiobook)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        showingFilePicker = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.folder, .audio, .mp3],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        Task {
                            print("📂 Processing import: \(url.lastPathComponent)")
                            
                            // Start accessing security-scoped resource
                            let accessing = url.startAccessingSecurityScopedResource()
                            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                            
                            var isDirectory: ObjCBool = false
                            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                                if isDirectory.boolValue {
                                    print("📁 Importing folder: \(url.lastPathComponent)")
                                    await audiobookManager.importAudiobookFolder(from: url)
                                } else {
                                    print("🎵 Importing single file: \(url.lastPathComponent)")
                                    await audiobookManager.importAudiobook(from: url)
                                }
                            } else {
                                print("🎵 Importing file (fallback): \(url.lastPathComponent)")
                                await audiobookManager.importAudiobook(from: url)
                            }
                        }
                    }
                case .failure(let error):
                    print("❌ Import failed: \(error.localizedDescription)")
                }
            }
            .refreshable {
                audiobookManager.fetchAudiobooks()
            }
            .onReceive(audiobookManager.$audiobookNeedingCover) { audiobook in
                showingImagePicker = (audiobook != nil)
                print(showingImagePicker)
            }
            .sheet(isPresented: $showingImagePicker) {
                if let audiobook = audiobookManager.audiobookNeedingCover {
                    ImagePickerView(audiobook: audiobook) { selectedImage in
                        audiobookManager.updateCoverImage(for: audiobook, with: selectedImage)
                    }
                }
            }
        }
    }
    
    private func deleteAudiobooks(offsets: IndexSet) {
        for index in offsets {
            let audiobook = filteredAudiobooks[index]
            audiobookManager.deleteAudiobook(audiobook)
        }
    }
}

struct AudiobookRowView: View {
    let audiobook: Audiobook
    
    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }
    
    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover Art
            Group {
                if let image = coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .clipped()
            
            // Book Info
            VStack(alignment: .leading, spacing: 4) {
                Text(audiobook.title ?? "Unknown Title")
                    .font(.headline)
                    .lineLimit(1)
                
                Text(audiobook.author ?? "Unknown Author")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let narrator = audiobook.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Progress Bar
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progressPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(height: 2)
                    
                    HStack {
                        Text(formatTime(audiobook.currentPosition))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if audiobook.isFinished {
                            Text("Finished")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Text(formatTime(audiobook.duration))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Status Indicator
            if audiobook.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if audiobook.currentPosition > 0 {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        
        if hours > 0 {
            return String(format: "%d:%02d:00", hours, minutes)
        } else {
            return String(format: "%d:%02d", minutes, Int(time) % 60)
        }
    }
}

#Preview {
    LibraryView()
}
