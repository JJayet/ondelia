import SwiftUI
import UIKit

struct TranscriptionView: View {
    let audiobook: AudiobookModel
    let currentChapterIndex: Int
    let currentTime: TimeInterval
    
    @StateObject private var transcriptionManager = TranscriptionManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var translationManager = TranslationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var transcriptionText = ""
    @State private var translatedText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var highlightedRange: Range<String.Index>?
    @State private var chapterTitle = NSLocalizedString("Transcription", comment: "Default chapter title for transcription")
    @State private var showingTranslation = false
    @State private var isTranslating = false
    
    var displayText: String {
        return showingTranslation && !translatedText.isEmpty ? translatedText : transcriptionText
    }
    
    var body: some View {
        NavigationStack {
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
                        Picker(NSLocalizedString("View", comment: "View picker label"), selection: $showingTranslation) {
                            Text(NSLocalizedString("Original", comment: "Original text option")).tag(false)
                            Text(NSLocalizedString("Translated", comment: "Translated text option")).tag(true)
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
                                Spacer()
                                TranscriptionLoader()
                                Spacer()
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
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                        .glassEffect()
                        .background(Color.glassTint, in: Capsule())
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
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
        .tint(themeManager.accentColor.color)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .alert(NSLocalizedString("Transcription Error", comment: "Transcription error alert title"), isPresented: $showingError) {
            Button(NSLocalizedString("OK", comment: "OK button")) {}
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
                    errorMessage = String(format: NSLocalizedString("Translation failed: %@", comment: "Translation error message"), error.localizedDescription)
                    showingError = true
                    isTranslating = false
                }
            }
        }
    }
    
    private func loadChapterTitle() {
        chapterTitle = getChapterTitle(for: audiobook, chapterIndex: currentChapterIndex)
    }
    
    private func getChapterTitle(for audiobook: AudiobookModel, chapterIndex: Int) -> String {
        guard let folderURL = audiobook.fileURL.map(URL.init(fileURLWithPath:)) else {
            return String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex)
        }
        
        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
        
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let chaptersData = manifest["chapters"] as? [[String: Any]],
              chapterIndex < chaptersData.count else {
            return String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex)
        }
        
        let chapterData = chaptersData[chapterIndex]
        
        // Try to get title, fallback to fileName without extension, then to Chapter N
        if let title = chapterData["title"] as? String, !title.isEmpty {
            return title
        } else if let fileName = chapterData["fileName"] as? String {
            let nameWithoutExtension = (fileName as NSString).deletingPathExtension
            return nameWithoutExtension.isEmpty ? String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex) : nameWithoutExtension
        } else {
            return String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex)
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

#Preview {
    TranscriptionView(
        audiobook: PreviewContent.audiobook(),
        currentChapterIndex: 0,
        currentTime: 150
    )
}
