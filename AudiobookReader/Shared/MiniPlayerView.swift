import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var globalAudioManager = GlobalAudioManager.shared
    @ObservedObject var statistics = ReadingStatistics()
    @State private var selectedAudiobook: Audiobook?
    
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
                
                HStack(spacing: 50) {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        HStack {
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
                            .frame(width: 30, height: 30)
                            .cornerRadius(8)
                            .clipped()
                            .padding(.leading, 8)
                            
                            // Book Info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(audiobook.title ?? NSLocalizedString("Unknown Title", comment: "Unknown title placeholder"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primaryText)
                                    .lineLimit(1)
                                
                                Text(audiobook.author ?? NSLocalizedString("Unknown Author", comment: "Unknown author placeholder"))
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
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
                            .controlSize(.large)
                            .padding(.trailing, 12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .onTapGesture {
                            selectedAudiobook = audiobook
                        }
                        .glassEffect()
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                    
                    Spacer().frame(width: 10)
                }
                
                Spacer().frame(height: 60)
            }
            .fullScreenCover(item: $selectedAudiobook) { audiobook in
                PlayerView(audiobook: audiobook)
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
