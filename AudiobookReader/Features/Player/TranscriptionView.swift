import SwiftUI

struct TranscriptionView: View {
    let audiobook: AudiobookModel

    // Read live rather than passed in: the transcript follows playback while the sheet is up,
    // and a value captured at presentation would freeze at the moment it opened.
    private let audio = GlobalAudioManager.shared
    private var currentChapterIndex: Int { audio.currentChapterIndex }
    private var currentTime: TimeInterval { audio.getCurrentTime() }

    private let transcriptionManager = SpeechTranscriptionManager.shared
    private let themeManager = ThemeManager.shared
    private let translationManager = TranslationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var transcription: TranscriptionResult?
    @State private var translatedText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var highlightedRange: Range<String.Index>?
    @State private var chapterTitle = NSLocalizedString("Transcription", comment: "Default chapter title for transcription")
    @State private var showingTranslation = false
    @State private var isTranslating = false
    
    private var transcriptionText: String { transcription?.text ?? "" }

    /// Word timings grouped into sentences. Empty for a transcript cached before timings were
    /// stored, and for the translation, which has no timeline of its own.
    private var sentences: [TranscriptSentence] {
        guard !showingTranslation, let transcription else { return [] }
        return TranscriptSentence.group(transcription.segments)
    }

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
                if !transcriptionText.isEmpty && themeManager.enableTranslation {
                    HStack {
                        Picker(NSLocalizedString("View", comment: "View picker label"), selection: $showingTranslation) {
                            Text(NSLocalizedString("Original", comment: "Original text option")).tag(false)
                            Text(NSLocalizedString("Translated", comment: "Translated text option")).tag(true)
                        }
                        .pickerStyle(.segmented)
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
                if transcriptionManager.isTranscribing {
                    Spacer()
                    TranscriptionLoader()
                    Spacer()
                } else if transcriptionText.isEmpty {
                    TranscriptionEmptyView {
                        startTranscription()
                    }
                } else if !sentences.isEmpty {
                    TranscriptSyncView(sentences: sentences, currentTime: currentTime) { time in
                        audio.seek(to: time)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            TranscriptionTextView(
                                text: displayText,
                                searchText: searchText,
                                highlightedRange: highlightedRange
                            )
                            .id("transcriptionText")
                            .padding()
                        }
                        .onChange(of: highlightedRange) { _, range in
                            guard range != nil else { return }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                        .glassEffect()
                        .background(Color.glassTint, in: Capsule())
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !transcriptionText.isEmpty && themeManager.enableTranslation {
                        Button(action: {
                            if translatedText.isEmpty {
                                translateText()
                            } else {
                                showingTranslation.toggle()
                            }
                        }) {
                            Image(systemName: showingTranslation ? "textformat" : "translate")
                                .foregroundStyle(showingTranslation ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                        }
                        .disabled(isTranslating)
                    }
                    
                    if !displayText.isEmpty {
                        ShareLink(item: displayText)
                    }
                    
                    Button(action: refreshTranscription) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(transcriptionManager.isTranscribing)
                }
            }
        }
        .alert(NSLocalizedString("Transcription Error", comment: "Transcription error alert title"), isPresented: $showingError) {
            Button(NSLocalizedString("OK", comment: "OK button")) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadChapterTitle()
            startTranscription()
        }
        .onChange(of: currentChapterIndex) { _, _ in
            loadChapterTitle()
            translatedText = "" // Reset translation when chapter changes
            showingTranslation = false
        }
    }
    
    private func translateText() {
        // The transcript is cached untranslated, so the source is whatever was recognised —
        // not the language currently selected in Settings.
        guard let transcription, !transcription.text.isEmpty else { return }
        
        isTranslating = true
        
        Task {
            do {
                let translated = try await translationManager.translateText(
                    transcription.text,
                    from: transcription.language,
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
        guard let folderURL = audiobook.resolvedFileURL else {
            return String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex + 1)
        }
        
        let manifestURL = folderURL.appendingPathComponent("audiobook_manifest.json")
        
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let chaptersData = manifest["chapters"] as? [[String: Any]],
              chapterIndex < chaptersData.count else {
            return String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex + 1)
        }
        
        let chapterData = chaptersData[chapterIndex]
        
        // Try to get title, fallback to fileName without extension, then to Chapter N
        if let title = chapterData["title"] as? String, !title.isEmpty {
            return title
        } else if let fileName = chapterData["fileName"] as? String {
            let nameWithoutExtension = (fileName as NSString).deletingPathExtension
            return nameWithoutExtension.isEmpty ? String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex + 1) : nameWithoutExtension
        } else {
            return String(format: NSLocalizedString("Chapter %d", comment: "Default chapter title with number"), chapterIndex + 1)
        }
    }
    
    private func startTranscription(bypassCache: Bool = false) {
        Task {
            do {
                transcription = try await transcriptionManager.transcribeCurrentChapter(
                    for: audiobook,
                    chapterIndex: currentChapterIndex,
                    bypassCache: bypassCache
                )
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    /// Refresh means "transcribe again", so it has to skip the cache the first run wrote.
    private func refreshTranscription() {
        transcription = nil
        translatedText = ""
        showingTranslation = false
        startTranscription(bypassCache: true)
    }
    
}

#Preview {
    TranscriptionView(audiobook: PreviewContent.audiobook())
}
