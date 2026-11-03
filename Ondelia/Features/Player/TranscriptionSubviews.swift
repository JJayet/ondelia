import SwiftUI

// MARK: - Header View
struct TranscriptionHeaderView: View {
    @Binding var searchText: String
    @Binding var transcriptionText: String
    @Binding var highlightedRange: Range<String.Index>?
    /// Occurrences in the timed transcript; nil hides the count and arrows.
    var matchCount: Int?
    var matchIndex: Int?
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    @State private var showingSearch = false
    
    var body: some View {
        VStack(spacing: 8) {
            if showingSearch {
                HStack {
                    TextField(NSLocalizedString("Search in transcription...", comment: "Search text field placeholder"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            searchInTranscription()
                            onNext()
                        }

                    if let matchCount, !searchText.isEmpty {
                        Text(matchCount == 0
                            ? NSLocalizedString("No results", comment: "No results title")
                            : String(
                                format: NSLocalizedString("%d of %d", comment: "Owned volumes out of the whole series"),
                                (matchIndex ?? 0) + 1,
                                matchCount
                            ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Button { withHapticFeedback { onPrevious() } } label: { Image(systemName: "chevron.up") }
                            .disabled(matchCount == 0)
                            .accessibilityLabel(NSLocalizedString("Previous result", comment: "Transcription search: go to the previous occurrence"))
                        Button { withHapticFeedback { onNext() } } label: { Image(systemName: "chevron.down") }
                            .disabled(matchCount == 0)
                            .accessibilityLabel(NSLocalizedString("Next result", comment: "Transcription search: go to the next occurrence"))
                    }

                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        withHapticFeedback {
                            searchText = ""
                            highlightedRange = nil
                            showingSearch = false
                        }
                    }
                    .foregroundStyle(.tint)
                }
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            HStack {
                Button(action: {
                    withHapticFeedback {
                        withAnimation { showingSearch.toggle() }
                    }
                    withAnimation {
                        if !showingSearch {
                            searchText = ""
                            highlightedRange = nil
                        }
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tint)
                }
                
                Spacer()
                
                // Placeholder for future controls
                Color.clear
                    .frame(width: 30, height: 30)
            }
            .padding(.horizontal)
            
            Divider()
        }
        .background(Color.secondaryBackground)
    }
    
    private func searchInTranscription() {
        guard !searchText.isEmpty else {
            highlightedRange = nil
            return
        }
        
        let range = transcriptionText.range(of: searchText, options: .caseInsensitive)
        highlightedRange = range
    }
}

// MARK: - Empty State View
struct TranscriptionEmptyView: View {
    let onStartTranscription: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundStyle(Color.secondaryText)
            
            Text(NSLocalizedString("No transcription available", comment: "No transcription available title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primaryText)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A streamed book has no file to transcribe: offer to download it. When the download lands,
/// the player switches to the file and the transcript loads.
struct TranscriptionStreamedView: View {
    let audiobook: AudiobookModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud")
                .font(.system(size: 60))
                .foregroundStyle(Color.secondaryText)

            Text(TranscriptionError.streamed.localizedDescription)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.primaryText)

            AudiobookShelfDownloadButton(book: audiobook)
                .frame(maxWidth: 280)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Text View
struct TranscriptionTextView: View {
    let text: String
    let searchText: String
    let highlightedRange: Range<String.Index>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Transcription metadata
            HStack {
                Label(NSLocalizedString("Transcribed", comment: "Transcription completed status"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
                
                Spacer()
            }
            
            Divider()
            
            // Main text content
            ScrollView {
                Text(attributedText)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.primaryBackground)
        .clipShape(.rect(cornerRadius: 12))
    }
    
    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        
        // Highlight search results
        if !searchText.isEmpty {
            // No highlight rather than a crash if the range does not map across.
            if let range = text.range(of: searchText, options: .caseInsensitive),
               let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].backgroundColor = .yellow
                attributed[attributedRange].foregroundColor = .black
            }
        }
        
        return attributed
    }
}
