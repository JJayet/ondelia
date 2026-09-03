import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct LibraryView: View {
    // State is internal (not private) so the content extensions in
    // LibraryView+Content.swift can drive it.
    let audiobookManager: AudiobookManager
    @Environment(\.playerRouter) private var playerRouter
    private let themeManager = ThemeManager.shared
    let statistics = ReadingStatistics.shared
    @State var showingStatistics = false
    @State var audiobookForImagePicker: AudiobookModel?
    @State var audiobookToRename: AudiobookModel?
    @State var newAudiobookTitle = ""
    /// One presentation slot for every alert this screen raises: SwiftUI only reliably drives one.
    @State var activeAlert: ActiveAlert?
    @State var viewMode: ViewMode = .list
    @State var sortOption: SortOption = .lastPlayed
    @State var filterOption: FilterOption = .all
    @State private var showingImporter = false
    @State private var searchText = ""
    // Dependency injection initializer to enable previews/tests to control state
    init(audiobookManager: AudiobookManager) {
        self.audiobookManager = audiobookManager
    }

    // Default initializer creates the manager on the main actor
    @MainActor
    init() {
        self.init(audiobookManager: AudiobookManager.shared)
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
        return filtered.sorted { sortOption.isOrderedBefore($0, $1) }
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

    /// Extracted from `body`: inline, the whole chain pushed the type checker over its limit.
    @ViewBuilder
    private var importBlockingOverlay: some View {
        if audiobookManager.isImporting {
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

    @ToolbarContentBuilder
    private var importToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingImporter = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .accessibilityLabel(NSLocalizedString("Import Audiobook", comment: "Import button accessibility label"))
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.importButton)
        }
    }

    /// Lifted out of `body`: the search field, the list/grid switch and the navigation
    /// modifiers together were more than the type checker would solve inline.
    private var libraryContent: some View {
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
        .overlay { importBlockingOverlay }
        .disabled(audiobookManager.isImporting)
        .toolbar { importToolbarItem }
        .onAppear {
            // Fetch audiobooks when the view first appears
            if audiobookManager.audiobooks.isEmpty && !audiobookManager.isLoadingLibrary {
                audiobookManager.fetchAudiobooks()
            }
        }
    }

    var body: some View {
        NavigationStack {
            libraryContent
        }
        .tint(themeManager.accentColor.color)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .sheet(isPresented: $showingImporter) {
            DocumentPickerView { urls in
                showingImporter = false
                handleImport(urls: urls)
            }
            .ignoresSafeArea()
        }
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
        .onChange(of: audiobookManager.audiobookNeedingCover?.id, initial: true) { _, _ in
            if let audiobook = audiobookManager.audiobookNeedingCover {
                audiobookForImagePicker = audiobook
            }
        }
        .onChange(of: audiobookManager.mergePrompt?.id, initial: true) { _, _ in
            guard let prompt = audiobookManager.mergePrompt else {
                if case .merge = activeAlert { activeAlert = nil }
                return
            }
            // One runloop hop: the offer is raised in the same main-actor update that clears the
            // import overlay and rebuilds the list, and SwiftUI can drop a modal requested inside
            // that. Asking on the next tick lets the view settle first.
            Task { @MainActor in
                guard audiobookManager.mergePrompt?.id == prompt.id else { return }
                activeAlert = .merge(prompt)
            }
        }
        .onChange(of: audiobookManager.importErrorMessage, initial: true) { _, message in
            if let message {
                activeAlert = .importFailed(message)
            } else if case .importFailed = activeAlert {
                activeAlert = nil
            }
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { if !$0 { dismissActiveAlert() } }
            ),
            presenting: activeAlert,
            actions: alertActions,
            message: alertMessage
        )
    }
}
