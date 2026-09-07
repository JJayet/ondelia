import SwiftUI

struct TranscriptionView: View {
    let audiobook: AudiobookModel

    // Read live rather than passed in: the transcript follows playback while the sheet is up,
    // and a value captured at presentation would freeze at the moment it opened. The playback
    // position itself is deliberately not read here: `TranscriptSyncView` watches it, so the
    // 4 Hz tick rebuilds the highlighted row and not this whole screen.
    private let audio = GlobalAudioManager.shared
    private var currentChapterIndex: Int { audio.currentChapterIndex }

    private let transcriptionManager = SpeechTranscriptionManager.shared
    private let translationManager = TranslationManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var transcription: TranscriptionResult?
    /// Grouped once per transcript. As a computed property it re-ran on every playback tick.
    @State private var groupedSentences: [TranscriptSentence] = []
    /// The one transcription in flight, so closing the sheet cancels it instead of leaving it
    /// to finish for nobody, and reopening never runs two at once.
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var translatedText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var highlightedRange: Range<String.Index>?
    @State private var chapterTitle = NSLocalizedString("Transcription", comment: "Default chapter title for transcription")
    @State private var showingTranslation = false
    @State private var isTranslating = false
    
    private var transcriptionText: String { transcription?.text ?? "" }

    /// The language to translate into, and the reason to offer translation at all: a book
    /// already spoken in the reader's language has nothing to translate to.
    private var readerLanguage: Locale.Language { Locale.current.language }

    private var canTranslate: Bool {
        guard let source = transcription?.language, !transcriptionText.isEmpty else { return false }
        return Locale.Language(identifier: source).languageCode != readerLanguage.languageCode
    }

    /// Where the chapter being transcribed starts in the book. The recogniser counts from the
    /// beginning of the chapter file; the player counts from the beginning of the book.
    private var chapterStart: TimeInterval {
        guard let tracks = audio.player?.tracks, tracks.indices.contains(currentChapterIndex) else {
            return 0
        }
        return tracks[currentChapterIndex].start
    }

    /// Word timings grouped into sentences, on the player's timeline. Empty for a transcript
    /// cached before timings were stored, and for the translation, which has no timeline of
    /// its own.
    private var sentences: [TranscriptSentence] {
        showingTranslation ? [] : groupedSentences
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
                if canTranslate {
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
                    TranscriptSyncView(sentences: sentences) { time in
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
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
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
                    Button(NSLocalizedString("Done", comment: "Done button")) { withHapticFeedback { dismiss() } }
                        .glassEffect()
                        .background(Color.glassTint, in: Capsule())
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if canTranslate {
                        Button(action: {
                            withHapticFeedback {}
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
                        .accessibilityLabel(
                            showingTranslation
                                ? NSLocalizedString("Show Original", comment: "Transcription: stop showing the translation")
                                : NSLocalizedString("Translate", comment: "Transcription: translate the text")
                        )
                    }

                    
                    Button(action: { withHapticFeedback { refreshTranscription() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(transcriptionManager.isTranscribing)
                    .accessibilityLabel(NSLocalizedString("Refresh Transcription", comment: "Transcription: transcribe the chapter again"))
                }
            }
        }
        .alert(NSLocalizedString("Transcription Error", comment: "Transcription error alert title"), isPresented: $showingError) {
            Button(NSLocalizedString("OK", comment: "OK button")) { withHapticFeedback {} }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadChapterTitle()
            startTranscription()
        }
        .onDisappear {
            transcriptionTask?.cancel()
            transcriptionTask = nil
        }
        .onChange(of: currentChapterIndex) { _, _ in
            loadChapterTitle()
            translatedText = "" // Reset translation when chapter changes
            showingTranslation = false
        }
    }
    
    private func translateText() {
        // The transcript is cached untranslated, so the source is whatever was recognised.
        guard let transcription, !transcription.text.isEmpty else { return }
        
        isTranslating = true
        
        Task {
            do {
                let translated = try await translationManager.translateText(
                    transcription.text,
                    from: transcription.language,
                    to: readerLanguage.languageCode?.identifier ?? "en"
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
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            do {
                let result = try await transcriptionManager.transcribeCurrentChapter(
                    for: audiobook,
                    chapterIndex: currentChapterIndex,
                    bypassCache: bypassCache
                )
                guard !Task.isCancelled else { return }
                transcription = result
                groupedSentences = TranscriptSentence.group(result.segments, offset: chapterStart)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    /// Refresh means "transcribe again", so it has to skip the cache the first run wrote.
    private func refreshTranscription() {
        transcription = nil
        groupedSentences = []
        translatedText = ""
        showingTranslation = false
        startTranscription(bypassCache: true)
    }
    
}

#Preview {
    TranscriptionView(audiobook: PreviewContent.audiobook())
}
