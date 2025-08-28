import SwiftUI
import UIKit

struct TranscriptionView: View {
    let audiobook: Audiobook
    let currentChapterIndex: Int
    let currentTime: TimeInterval
    
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var translationManager = TranslationManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    @State private var transcriptionText = ""
    @State private var translatedText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var highlightedRange: Range<String.Index>?
    @State private var chapterTitle = "Transcription"
    @State private var showingTranslation = false
    @State private var isTranslating = false
    
    var displayText: String {
        return showingTranslation && !translatedText.isEmpty ? translatedText : transcriptionText
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with controls
                TranscriptionHeaderView(
                    searchText: $searchText,
                    transcriptionText: .constant(displayText),
                    highlightedRange: $highlightedRange
                )
                
                // Translation toggle if available
                if !transcriptionText.isEmpty && TranslationManager.isAvailable && themeManager.enableTranslation {
                    HStack {
                        Picker("View", selection: $showingTranslation) {
                            Text("Original").tag(false)
                            Text("Translation").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: showingTranslation) { _, shouldTranslate in
                            if shouldTranslate && translatedText.isEmpty {
                                translateText()
                            }
                        }
                        
                        if isTranslating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.secondaryBackground)
                }
                
                // Main transcription content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if transcriptionManager.isTranscribing {
                                TranscriptionLoadingView(progress: transcriptionManager.transcriptionProgress)
                            } else if transcriptionText.isEmpty {
                                TranscriptionEmptyView {
                                    startTranscription()
                                }
                            } else {
                                TranscriptionTextView(
                                    text: displayText,
                                    searchText: searchText,
                                    highlightedRange: highlightedRange,
                                    currentTime: currentTime
                                )
                                .id("transcriptionText")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: highlightedRange) { _, range in
                        if range != nil {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo("transcriptionText", anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle(chapterTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }.glassEffect()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !transcriptionText.isEmpty && TranslationManager.isAvailable && themeManager.enableTranslation {
                            Button(action: {
                                if translatedText.isEmpty {
                                    translateText()
                                } else {
                                    showingTranslation.toggle()
                                }
                            }) {
                                Image(systemName: showingTranslation ? "textformat" : "translate")
                                    .foregroundColor(showingTranslation ? .primary : .accentColor)
                            }
                            .disabled(isTranslating)
                        }
                        
                        if !displayText.isEmpty {
                            Button(action: shareTranscription) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        
                        Button(action: refreshTranscription) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(transcriptionManager.isTranscribing)
                    }
                }
            }
        }
        .accentColor(themeManager.accentColor.color)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .alert("Transcription Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadChapterTitle()
            loadTranscription()
        }
        .onChange(of: currentChapterIndex) { _, _ in
            loadChapterTitle()
            translatedText = "" // Reset translation when chapter changes
            showingTranslation = false
        }
    }
    
    private func translateText() {
        guard !transcriptionText.isEmpty && TranslationManager.isAvailable else { return }
        
        isTranslating = true
        
        Task {
            do {
                let translated = try await translationManager.translateText(
                    transcriptionText,
                    from: themeManager.transcriptionLanguage.rawValue,
                    to: themeManager.translationTargetLanguage.rawValue
                )
                
                await MainActor.run {
                    translatedText = translated
                    showingTranslation = true
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Translation failed: \(error.localizedDescription)"
                    showingError = true
                    isTranslating = false
                }
            }
        }
    }
    
    private func loadChapterTitle() {
        chapterTitle = getChapterTitle(for: audiobook, chapterIndex: currentChapterIndex)
    }
    
    private func getChapterTitle(for audiobook: Audiobook, chapterIndex: Int) -> String {
        guard let folderURL = audiobook.fileURL.map(URL.init(fileURLWithPath:)) else {
            return "Chapter \(chapterIndex)"
        }
        
        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
        
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let chaptersData = manifest["chapters"] as? [[String: Any]],
              chapterIndex < chaptersData.count else {
            return "Chapter \(chapterIndex)"
        }
        
        let chapterData = chaptersData[chapterIndex]
        
        // Try to get title, fallback to fileName without extension, then to Chapter N
        if let title = chapterData["title"] as? String, !title.isEmpty {
            return title
        } else if let fileName = chapterData["fileName"] as? String {
            let nameWithoutExtension = (fileName as NSString).deletingPathExtension
            return nameWithoutExtension.isEmpty ? "Chapter \(chapterIndex)" : nameWithoutExtension
        } else {
            return "Chapter \(chapterIndex)"
        }
    }
    
    private func loadTranscription() {
        Task {
            do {
                transcriptionText = try await transcriptionManager.transcribeCurrentChapter(
                    for: audiobook,
                    currentChapterIndex: currentChapterIndex
                )
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func startTranscription() {
        Task {
            do {
                transcriptionText = try await transcriptionManager.transcribeCurrentChapter(
                    for: audiobook,
                    currentChapterIndex: currentChapterIndex
                )
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func refreshTranscription() {
        transcriptionText = ""
        translatedText = ""
        showingTranslation = false
        startTranscription()
    }
    
    private func shareTranscription() {
        let activityViewController = UIActivityViewController(
            activityItems: [displayText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityViewController, animated: true)
        }
    }
}

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
                    TextField("Search in transcription...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchInTranscription()
                        }
                    
                    Button("Cancel") {
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
            
            Text("Transcribing audio...")
                .font(.headline)
                .foregroundColor(.primaryText)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(maxWidth: 200)
            
            Text(String(format: "%.0f%% complete", progress * 100))
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
            
            Text("No Transcription Available")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
            
            Text("Tap the button below to generate a transcription of this chapter using on-device speech recognition.")
                .font(.body)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: onStartTranscription) {
                Label("Start Transcription", systemImage: "mic")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
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
                Label("Transcribed", systemImage: "checkmark.circle")
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

// MARK: - Preview
#Preview {
    TranscriptionView(
        audiobook: Audiobook(),
        currentChapterIndex: 0,
        currentTime: 150
    )
}
