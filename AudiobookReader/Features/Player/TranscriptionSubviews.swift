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
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchInTranscription()
                        }
                    
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        searchText = ""
                        highlightedRange = nil
                        showingSearch = false
                    }
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            HStack {
                Button(action: {
                    withAnimation {
                        showingSearch.toggle()
                        if !showingSearch {
                            searchText = ""
                            highlightedRange = nil
                        }
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.accentColor)
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
    
    private var currentChapterIndex: Int {
        // This should be passed from parent, using 0 as fallback
        return 0
    }
}

// MARK: - Loading View
struct TranscriptionLoadingView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)
                .scaleEffect(1.0 + sin(Date().timeIntervalSince1970 * 2) * 0.1)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: UUID())
            
            Text(NSLocalizedString("Transcribing...", comment: "Transcription in progress text"))
                .font(.headline)
                .foregroundColor(.primaryText)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(maxWidth: 200)
            
            Text(String(format: NSLocalizedString("%.0f%% complete", comment: "Transcription progress percentage"), progress * 100))
                .font(.caption)
                .foregroundColor(.secondaryText)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View
struct TranscriptionEmptyView: View {
    let onStartTranscription: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.secondaryText)
            
            Text(NSLocalizedString("No transcription available", comment: "No transcription available title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
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
    let currentTime: TimeInterval
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Transcription metadata
            HStack {
                Label(NSLocalizedString("Transcribed", comment: "Transcription completed status"), systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Spacer()
                
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
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
        .cornerRadius(12)
    }
    
    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        
        // Highlight search results
        if !searchText.isEmpty {
            let searchRange = text.range(of: searchText, options: .caseInsensitive)
            if let range = searchRange {
                let attributedRange = AttributedString.Index(range.lowerBound, within: attributed)!..<AttributedString.Index(range.upperBound, within: attributed)!
                attributed[attributedRange].backgroundColor = .yellow
                attributed[attributedRange].foregroundColor = .black
            }
        }
        
        return attributed
    }
}
