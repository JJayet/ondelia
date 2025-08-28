import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @State private var showingFilePicker = false
    @State private var selectedAudioURL: URL?
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack {
                Text(NSLocalizedString("Audiobook Reader", comment: "App title"))
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(NSLocalizedString("Phase 1 - Core Audio Engine", comment: "Development phase subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Audio File Selection
            if selectedAudioURL == nil {
                VStack(spacing: 16) {
                    Image(systemName: "doc.audio")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Button(NSLocalizedString("Select Audio File", comment: "Select audio file button")) {
                        showingFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Now Playing Info
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text(NSLocalizedString("Sample Audiobook", comment: "Sample audiobook title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(NSLocalizedString("Unknown Author", comment: "Unknown author placeholder"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                // Progress Bar
                VStack(spacing: 8) {
                    ProgressView(value: audioEngine.currentTime, total: audioEngine.duration)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    HStack {
                        Text(formatTime(audioEngine.currentTime))
                        Spacer()
                        Text(formatTime(audioEngine.duration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Playback Controls
                HStack(spacing: 40) {
                    Button(action: { audioEngine.skipBackward() }) {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                    }
                    
                    Button(action: { audioEngine.togglePlayback() }) {
                        Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                    }
                    
                    Button(action: { audioEngine.skipForward() }) {
                        Image(systemName: "goforward.15")
                            .font(.title)
                    }
                }
                .foregroundColor(.blue)
                
                // Playback Speed Control
                VStack(spacing: 8) {
                    Text(String(format: NSLocalizedString("Playback Speed: %.1fx", comment: "Playback speed display"), audioEngine.playbackRate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            Button("\(String(format: "%.2fx", speed))") {
                                audioEngine.setPlaybackRate(Float(speed))
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(audioEngine.playbackRate == Float(speed) ? .white : .blue)
                            .background(audioEngine.playbackRate == Float(speed) ? Color.blue : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                }
                
                Button(NSLocalizedString("Change Audio File", comment: "Change audio file button")) {
                    showingFilePicker = true
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedAudioURL = url
                    
                    // Start accessing security-scoped resource
                    if url.startAccessingSecurityScopedResource() {
                        audioEngine.loadAudio(url: url)
                        
                        // Stop accessing when done (in a real app, you'd manage this better)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                }
            case .failure(let error):
                print("Failed to select file: \(error)")
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
