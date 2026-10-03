import SwiftUI

struct TranscriptionView: View {
    let audiobook: AudiobookModel

    // Read live rather than passed in: the transcript follows playback while the sheet is up,
    // and a value captured at presentation would freeze at the moment it opened. The playback
    // position itself is deliberately not read in `body`: `TranscriptSyncView` watches it, so
    // the 4 Hz tick rebuilds the highlighted row and not this whole screen; this view polls it
    // every couple of seconds to notice the playhead leaving the window.
    private let audio = GlobalAudioManager.shared
    private let transcriptionManager = SpeechTranscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Everything one load depends on, frozen when it starts: the window, the offset and
    /// whether to skip the cache. A result is grouped with the offset it was requested under,
    /// never with whatever the player is on when it completes.
    private struct LoadKey: Equatable {
        var request: TranscriptionRequest?
        var bypassCache = false
        var generation = 0
    }

    @State private var loadKey = LoadKey()
    @State private var transcription: TranscriptionResult?
    /// Grouped once per transcript. As a computed property it re-ran on every playback tick.
    @State private var groupedSentences: [TranscriptSentence] = []
    @State private var failed = false
    /// The window is streamed from the server, which the recogniser cannot read.
    @State private var streamed = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var highlightedRange: Range<String.Index>?
    @State private var showingLanguagePicker = false

    /// The book's chosen language. Stored per book; changing it re-keys the request, and the
    /// cache is keyed by language too, so the old transcript cannot come back in its place.
    private var languageOverride: Binding<String?> {
        Binding(
            get: { TranscriptionRequest.storedLanguage(for: audiobook.id) },
            set: { language in
                TranscriptionRequest.storeLanguage(language, for: audiobook.id)
                updateRequest()
            }
        )
    }

    private var request: TranscriptionRequest? { loadKey.request }

    /// The partial transcript of this window while it is still being recognised.
    private var live: SpeechTranscriptionManager.LiveTranscript? {
        guard let live = transcriptionManager.live, live.request == request else { return nil }
        return live
    }

    private var isLoaded: Bool { transcription != nil }

    private var displayText: String { transcription?.text ?? live?.text ?? "" }

    /// Word timings grouped into sentences, on the player's timeline. Empty for a transcript
    /// cached before timings were stored.
    private var sentences: [TranscriptSentence] {
        if isLoaded { return groupedSentences }
        return TranscriptSentence.group(live?.segments ?? [], offset: request?.trackStart ?? 0)
    }

    private var chapterTitle: String {
        guard let request else {
            return NSLocalizedString("Transcription", comment: "Default chapter title for transcription")
        }
        return request.title ?? getChapterTitle(for: audiobook, chapterIndex: request.trackIndex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TranscriptionHeaderView(
                    searchText: $searchText,
                    transcriptionText: .constant(displayText),
                    highlightedRange: $highlightedRange
                )

                if !isLoaded, !displayText.isEmpty {
                    // Text is arriving: a thin bar shows how much of the window is left.
                    ProgressView(value: transcriptionManager.transcriptionProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                }

                if displayText.isEmpty {
                    if streamed {
                        TranscriptionStreamedView(audiobook: audiobook)
                    } else if request == nil || failed {
                        TranscriptionEmptyView { withHapticFeedback { retry() } }
                    } else {
                        Spacer()
                        TranscriptionLoader(
                            progress: transcriptionManager.transcriptionProgress,
                            isDownloadingModel: transcriptionManager.isDownloadingModel
                        )
                        Spacer()
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
                // Plain: the bar already draws glass around its items, and a second capsule
                // on Done sat over the neighbouring buttons.
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { withHapticFeedback { dismiss() } }
                }

                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: { withHapticFeedback { showingLanguagePicker = true } }) {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel(NSLocalizedString("Transcription language", comment: "Transcription language picker title"))

                    Button(action: { withHapticFeedback { refreshTranscription() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(request == nil || (!isLoaded && !failed))
                    .accessibilityLabel(NSLocalizedString("Refresh Transcription", comment: "Transcription: transcribe the chapter again"))
                }
            }
        }
        .sheet(isPresented: $showingLanguagePicker, onDismiss: {
            TranscriptionRequest.markLanguageAsked(for: audiobook.id)
            // Picking a language re-keyed the request already; keeping the default did not,
            // so kick the load that waited on the answer.
            loadKey.generation += 1
        }) {
            TranscriptionLanguagePicker(audioURL: request?.url, selection: languageOverride)
        }
        // First transcript of a book: ask which language it is in, with the guess from the file
        // preselected, rather than recognising an English book as French for a whole chapter.
        // Once the file is known, so the picker can name the guess.
        .onChange(of: request?.url, initial: true) { _, url in
            guard url?.isFileURL == true, !TranscriptionRequest.languageAsked(for: audiobook.id) else { return }
            showingLanguagePicker = true
        }
        .alert(NSLocalizedString("Transcription Error", comment: "Transcription error alert title"), isPresented: $showingError) {
            Button(NSLocalizedString("OK", comment: "OK button")) { withHapticFeedback {} }
        } message: {
            Text(errorMessage)
        }
        // Cancelled and restarted whenever the key changes, so a stale load can never deliver
        // into a newer window; cancelled with the sheet, so nothing runs on for nobody.
        .task(id: loadKey) { await load(loadKey) }
        .task { await followPlayhead() }
    }

    // MARK: - Windows

    /// Moves to the window under the playhead whenever playback leaves the current one.
    private func followPlayhead() async {
        while !Task.isCancelled {
            updateRequest()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func updateRequest() {
        let time = audio.getCurrentTime()
        let language = TranscriptionRequest.storedLanguage(for: audiobook.id)
        guard let next = makeRequest(at: time, language: language) else { return }
        // Same window, unless its audio moved: a streamed book that finished downloading.
        if let request, request.contains(bookTime: time), request.language == language, request.url == next.url { return }
        loadKey = LoadKey(request: next)
    }

    /// The window after `request`, so it can be warmed while this one is read.
    private func nextRequest(after request: TranscriptionRequest) -> TranscriptionRequest? {
        makeRequest(at: request.bookRange.upperBound + 0.5, language: request.language)
    }

    private func makeRequest(at time: TimeInterval, language: String?) -> TranscriptionRequest? {
        TranscriptionRequest.make(
            audiobookID: audiobook.id,
            chapters: audiobook.sortedChapters,
            tracks: audio.player?.tracks ?? [],
            time: time,
            language: language
        )
    }

    // MARK: - Loading

    private func load(_ key: LoadKey) async {
        guard !Task.isCancelled, key == loadKey else { return }
        transcription = nil
        groupedSentences = []
        failed = false
        streamed = false
        guard let request = key.request else { return }
        // Not before the language question is answered: a chapter recognised in the wrong
        // language is a chapter recognised twice. The picker's dismissal restarts this load.
        // A streamed window goes on, to find a cached transcript or say why there is none.
        guard TranscriptionRequest.languageAsked(for: audiobook.id) || !request.url.isFileURL else { return }

        do {
            let result = try await transcriptionManager.transcribe(request, bypassCache: key.bypassCache)
            // Cache reads can finish successfully after cancellation. Only the current load
            // may publish text or start prefetching another window.
            guard !Task.isCancelled, key == loadKey else { return }
            transcription = result
            groupedSentences = TranscriptSentence.group(result.segments, offset: request.trackStart)

            // Warm the next window while this one is read, so crossing into it finds a cache hit.
            if let next = nextRequest(after: request), next != request {
                _ = try? await transcriptionManager.transcribe(next)
            }
        } catch is CancellationError {
            return
        } catch TranscriptionError.streamed {
            guard !Task.isCancelled, key == loadKey else { return }
            streamed = true
        } catch {
            guard !Task.isCancelled, key == loadKey else { return }
            errorMessage = error.localizedDescription
            showingError = true
            failed = true
        }
    }

    private func retry() {
        if request == nil {
            updateRequest()
        } else {
            loadKey.generation += 1
        }
    }

    /// Refresh means "transcribe again", so it has to skip the cache the first run wrote.
    private func refreshTranscription() {
        loadKey = LoadKey(request: request, bypassCache: true, generation: loadKey.generation + 1)
    }

    // MARK: - Titles

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
}

#Preview {
    TranscriptionView(audiobook: PreviewContent.audiobook())
}
