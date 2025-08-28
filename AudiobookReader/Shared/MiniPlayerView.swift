import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var globalAudioManager = GlobalAudioManager.shared
    @ObservedObject var statistics = ReadingStatistics()
    @State private var selectedAudiobook: Audiobook?
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    
    private var coverImage: UIImage? {
        guard let data = globalAudioManager.currentAudiobook?.coverImageData else { return nil }
        return UIImage(data: data)
    }
    
    private var currentTime: TimeInterval {
        if globalAudioManager.useMultiFileEngine {
            return globalAudioManager.multiFileAudioEngine?.currentTime ?? 0
        } else {
            return globalAudioManager.audioEngine?.currentTime ?? 0
        }
    }
    
    private var duration: TimeInterval {
        if globalAudioManager.useMultiFileEngine {
            return globalAudioManager.multiFileAudioEngine?.duration ?? 1
        } else {
            return globalAudioManager.audioEngine?.duration ?? 1
        }
    }
    
    private var isPlaying: Bool {
        // Use the published playback state for better UI responsiveness
        return globalAudioManager.playbackState == .playing
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var body: some View {
        if globalAudioManager.showMiniPlayer, let audiobook = globalAudioManager.currentAudiobook {
            VStack(spacing: 0) {
                Spacer()
                
                HStack(spacing: 0) {
                    Spacer()
                    
                    // Mini Player Card
                    VStack(spacing: 0) {
                        // Progress Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 2)
                                
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geometry.size.width * progress, height: 2)
                            }
                        }
                        .frame(height: 2)
                        
                        // Main Content
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
                                        .foregroundColor(.secondaryText)
                                }
                            }
                            .frame(width: 50, height: 50)
                            .background(Color.secondaryBackground)
                            .cornerRadius(8)
                            .clipped()
                            
                            // Book Info
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audiobook.title ?? "Unknown Title")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primaryText)
                                    .lineLimit(1)
                                
                                Text(audiobook.author ?? "Unknown Author")
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Play/Pause Button
                            Button {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    if isPlaying {
                                        globalAudioManager.pausePlayback()
                                    } else {
                                        globalAudioManager.resumePlayback()
                                    }
                                }
                                
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                            
                            // Close Button
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    globalAudioManager.showMiniPlayer = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.cardBackground)
                        .onTapGesture {
                            selectedAudiobook = audiobook
                        }
                    }
                    .cornerRadius(16)
//                    .background(
//                        Group {
//                            if #available(iOS 26.0, *) {
//                                Color.clear.glassEffect(.regular.interactive())
//                            } else {
//                                Color.clear
//                            }
//                        }
//                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                    .offset(x: dragOffset.width, y: dragOffset.height)
                    .scaleEffect(isDragging ? 0.95 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                dragOffset = CGSize(
                                    width: max(-50, min(50, value.translation.width)),
                                    height: max(-100, min(20, value.translation.height))
                                )
                            }
                            .onEnded { value in
                                isDragging = false
                                
                                // Dismiss if dragged down significantly
                                if value.translation.height > 80 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        globalAudioManager.showMiniPlayer = false
                                    }
                                }
                                
                                // Reset position
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    dragOffset = .zero
                                }
                            }
                    )
                    
                    Spacer().frame(width: 16)
                }
                
                Spacer().frame(height: 100) // Bottom safe area
            }
            .fullScreenCover(item: $selectedAudiobook) { audiobook in
                PlayerView(audiobook: audiobook, statistics: statistics)
            }
        }
    }
}

struct MiniPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()
            MiniPlayerView()
        }
    }
}
