import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct LibraryView: View {
    // State is internal (not private) so the content extensions in
    // LibraryView+Content.swift can drive it.
    @StateObject var audiobookManager: AudiobookManager
    @Environment(\.playerRouter) private var playerRouter
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject var statistics = ReadingStatistics.shared
    @State var showingStatistics = false
    @State var audiobookForImagePicker: AudiobookModel?
    @State var showingRenameAlert = false
    @State var audiobookToRename: AudiobookModel?
    @State var newAudiobookTitle = ""
    @State var viewMode: ViewMode = .list
    @State var sortOption: SortOption = .lastPlayed
    @State var filterOption: FilterOption = .all
    @State private var showingImporter = false
    @State private var searchText = ""
    // Dependency injection initializer to enable previews/tests to control state
    init(audiobookManager: AudiobookManager) {
        _audiobookManager = StateObject(wrappedValue: audiobookManager)
    }

    // Default initializer creates the manager on the main actor
    @MainActor
    init() {
        self.init(audiobookManager: AudiobookManager.shared)
    }

    private var allowedFileTypes: [UTType] {
        var types: [UTType] = [.folder, .audio, .mp3, .zip]
        if let m4a = UTType(filenameExtension: "m4a") {
            types.append(m4a)
        }
        if let m4b = UTType(filenameExtension: "m4b") {
            types.append(m4b)
        }
        return types
    }

    var filteredAudiobooks: [AudiobookModel] {
        let source = searchText.isEmpty
            ? audiobookManager.audiobooks
            : audiobookManager.searchAudiobooks(query: searchText)
        // Filter in pure Swift to avoid KVC/NSPredicate on SwiftData models
        let filtered: [AudiobookModel] = {
            switch filterOption {
            case .all:
                return source
            case .inProgress:
                return source.filter { $0.currentPosition > 0 && !$0.isFinished }
            case .completed:
                return source.filter { $0.isFinished }
            case .notStarted:
                return source.filter { $0.currentPosition == 0 }
            }
        }()
        // Sort with SortDescriptor for consistency
        let descriptor = sortOption.descriptor
        return filtered.sorted { descriptor.compare($0, $1) == .orderedAscending }
    }

    // MARK: - Actions
    func playAndPresent(_ audiobook: AudiobookModel) {
        let audio = GlobalAudioManager.shared
        audio.loadAudiobook(audiobook)
        audio.startPlayback()
        playerRouter?.present(audiobook)
    }

    var continueReadingBooks: [AudiobookModel] {
        audiobookManager.audiobooks
            .filter { $0.currentPosition > 0 && !$0.isFinished }
            .sorted { $0.lastPlayed > $1.lastPlayed }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Import Handler (delegates to manager's queue w/ progress)
    private func handleImport(urls: [URL]) {
        audiobookManager.handleImportRequest(urls: urls)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField(
                    NSLocalizedString("Search your audiobooks", comment: "Library search field prompt"),
                    text: $searchText
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityIdentifiers.Library.searchBar)
                .padding(.horizontal)
                .padding(.top, 8)

                if viewMode == .list {
                    listModeContent
                } else {
                    gridModeContent
                }
            }
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Library", comment: "Library navigation title"))
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                // The import-style question comes first: no spinner behind it, and its buttons stay live.
                if audiobookManager.isImporting && audiobookManager.folderImportPrompt == nil {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().scaleEffect(1.2)
                            Text(NSLocalizedString("Please be patient while your file(s) are being imported", comment: "Blocking import message"))
                                .font(.body)
                                .foregroundColor(.primaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(20)
                    }
                    .transition(.opacity)
                }
            }
            .disabled(audiobookManager.isImporting && audiobookManager.folderImportPrompt == nil)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingImporter = true }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .accessibilityLabel(NSLocalizedString("Import Audiobook", comment: "Import button accessibility label"))
                    .accessibilityIdentifier(AccessibilityIdentifiers.Library.importButton)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: allowedFileTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    handleImport(urls: urls)
                case .failure(let error):
                    print("❌ Import failed: \(error.localizedDescription)")
                }
            }
            .onAppear {
                // Fetch audiobooks when the view first appears
                if audiobookManager.audiobooks.isEmpty && !audiobookManager.isLoadingLibrary {
                    audiobookManager.fetchAudiobooks()
                }
            }
        }
        .tint(themeManager.accentColor.color)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .sheet(isPresented: $showingStatistics) {
            StatisticsView(statistics: statistics)
        }
        .refreshable {
            withAnimation(.easeInOut(duration: 0.5)) {
                audiobookManager.fetchAudiobooks()
            }
        }
        .sheet(item: $audiobookForImagePicker) { audiobook in
            ImagePickerView(audiobook: audiobook) { image in
                audiobookManager.updateCoverImage(for: audiobook, with: image)
                audiobookForImagePicker = nil
            }
        }
        .onReceive(audiobookManager.$audiobookNeedingCover) { audiobook in
            if let audiobook = audiobook {
                audiobookForImagePicker = audiobook
            }
        }
        .alert(NSLocalizedString("Rename Audiobook", comment: "Alert title for renaming"), isPresented: $showingRenameAlert) {
            TextField(NSLocalizedString("New title", comment: "Placeholder for new title"), text: $newAudiobookTitle)
                .onSubmit {
                    if let audiobook = audiobookToRename, !newAudiobookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        audiobookManager.renameAudiobook(audiobook, newTitle: newAudiobookTitle)
                        audiobookToRename = nil
                        newAudiobookTitle = ""
                    }
                }

            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                audiobookToRename = nil
                newAudiobookTitle = ""
            }

            Button(NSLocalizedString("Save", comment: "Save button")) {
                if let audiobook = audiobookToRename, !newAudiobookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    audiobookManager.renameAudiobook(audiobook, newTitle: newAudiobookTitle)
                }
                audiobookToRename = nil
                newAudiobookTitle = ""
            }
            .disabled(newAudiobookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(String(format: NSLocalizedString("Enter a new title for '%@'", comment: "Alert message for renaming"), audiobookToRename?.title ?? ""))
        }
        .alert(
            NSLocalizedString("Import Folder", comment: "Folder import style alert title"),
            isPresented: Binding(
                get: { audiobookManager.folderImportPrompt != nil },
                set: { if !$0 { audiobookManager.folderImportPrompt?.respond(false) } }
            ),
            presenting: audiobookManager.folderImportPrompt
        ) { prompt in
            Button(NSLocalizedString("One Audiobook", comment: "Import folder as a single audiobook")) {
                prompt.respond(false)
            }
            Button(NSLocalizedString("Separate Audiobooks", comment: "Import each file as its own audiobook")) {
                prompt.respond(true)
            }
        } message: { prompt in
            Text(String(
                format: NSLocalizedString(
                    "'%@' contains %d audio files. Import them as one audiobook with chapters, or as separate audiobooks?",
                    comment: "Folder import style alert message"
                ),
                prompt.folderName,
                prompt.fileCount
            ))
        }
        .alert(
            NSLocalizedString("Import Failed", comment: "Import error alert title"),
            isPresented: Binding(
                get: { audiobookManager.importErrorMessage != nil },
                set: { if !$0 { audiobookManager.importErrorMessage = nil } }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "Dismiss alert button"), role: .cancel) {
                audiobookManager.importErrorMessage = nil
            }
        } message: {
            Text(audiobookManager.importErrorMessage ?? "")
        }
    }
}
