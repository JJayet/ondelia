import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Lock Screen View
struct AudiobookLiveActivityView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Cover art
                if let coverImageData = NowPlayingSharedStore.coverImageData(),
                   let coverImage = UIImage(data: coverImageData) {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "book.fill")
                                .foregroundColor(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(context.state.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let chapterTitle = context.state.chapterTitle {
                        Text(chapterTitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    if context.state.playbackRate != 1.0 {
                        Text("\(String(format: "%.1fx", context.state.playbackRate))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress bar with time
            VStack(spacing: 6) {
                Group {
                    if context.state.isPlaying {
                        ProgressView(timerInterval: context.state.playbackDateInterval, countsDown: false)
                    } else {
                        ProgressView(value: context.state.progress)
                    }
                }
                .progressViewStyle(LinearProgressViewStyle())
                    .tint(.accentColor)
                
                HStack {
                    Text(context.state.formattedCurrentTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if context.state.isPlaying {
                        Text("-\(context.state.formattedRemainingTime)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(context.state.formattedDuration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Dynamic Island Expanded View
struct AudiobookExpandedView: View {
    let context: ActivityViewContext<AudiobookLiveActivityAttributes>
    
    var body: some View {
        VStack(spacing: 16) {
            // Top section with cover and info
            HStack(spacing: 12) {
                if let coverImageData = NowPlayingSharedStore.coverImageData(),
                   let coverImage = UIImage(data: coverImageData) {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "book.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(context.state.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let chapterTitle = context.state.chapterTitle {
                        Text(chapterTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            
            // Progress and controls
            VStack(spacing: 8) {
                HStack {
                    Text(context.state.formattedCurrentTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(context.state.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Group {
                    if context.state.isPlaying {
                        ProgressView(timerInterval: context.state.playbackDateInterval, countsDown: false)
                    } else {
                        ProgressView(value: context.state.progress)
                    }
                }
                .progressViewStyle(LinearProgressViewStyle())
                    .tint(.accentColor)
                
                // Playback controls
                HStack(spacing: 24) {
                    Button(intent: SkipBackwardIntent()) {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .frame(width: 44, height: 44)
                    
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .frame(width: 52, height: 52)
                    
                    Button(intent: SkipForwardIntent()) {
                        Image(systemName: "goforward.30")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .frame(width: 44, height: 44)
                    
                    if context.state.playbackRate != 1.0 {
                        Text("\(String(format: "%.1fx", context.state.playbackRate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
    }
}
