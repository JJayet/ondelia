import SwiftUI

// MARK: - Header View
struct TranscriptionHeaderView: View {
    @Binding var searchText: String
    @Binding var transcriptionText: String
    @Binding var highlightedRange: Range<String.Index>?
    
    @State private var showingSearch = false
    
    var body: some View {
        VStack(spacing: 8) {
            if showingSearch {
                HStack {
                    TextField(NSLocalizedString("Search in transcription...", comment: "Search text field placeholder"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            searchInTranscription()
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
