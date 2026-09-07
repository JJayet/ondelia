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
    /// The book whose detail screen is pushed, if any.
    @State var audiobookForDetail: AudiobookModel?
    @State var audiobookForHardcover: AudiobookModel?
    @State var audiobookToRename: AudiobookModel?
    @State var newAudiobookTitle = ""
    /// One presentation slot for every alert this screen raises: SwiftUI only reliably drives one.
    @State var activeAlert: ActiveAlert?
    // Kept across launches: re-picking the same sort and view on every cold start was noise.
    @AppStorage("library.viewMode") var viewMode: ViewMode = .list
    @AppStorage("library.sortOption") var sortOption: SortOption = .lastPlayed
    @AppStorage("library.filterOption") var filterOption: FilterOption = .all
    /// Series grouping is Hardcover's doing, so it can be switched off from the banner.
    @AppStorage("library.groupSeries") var groupSeries = true
    /// Books per row in grid mode: 2, 3 or 4.
    @AppStorage("library.gridColumns") var gridColumns = 2
    @State var showingImporter = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
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
        let source = audiobookManager.audiobooks
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

    /// The filtered library split into series and everything else. Computed whether or not
    /// grouping is on, so the banner can say what turning it on would do.
    var grouping: (series: [SeriesGroup], standalone: [AudiobookModel]) {
        SeriesGroup.group(filteredAudiobooks)
    }

    // MARK: - Actions
    func playAndPresent(_ audiobook: AudiobookModel) {
        withHapticFeedback(.medium) {}
        let audio = GlobalAudioManager.shared
        audio.loadAudiobook(audiobook)
        audio.startPlaybackAfterOpeningBook()
        playerRouter?.present(audiobook)
    }

    /// The book-actions menu closures, wired to this screen's own alert/sheet state so the
    /// menu can be shown from the grid, the list rows and the detail screen alike.
    var bookActions: BookActions {
        BookActions(
            rename: { audiobook in
                audiobookToRename = audiobook
                newAudiobookTitle = audiobook.title ?? ""
                activeAlert = .rename
            },
            changeCover: { audiobookForImagePicker = $0 },
            linkHardcover: { audiobookForHardcover = $0 },
            delete: { activeAlert = .confirmDelete($0) }
        )
    }

    /// A queued book played by hand leaves the queue: it is no longer "next".
    func playQueued(_ audiobook: AudiobookModel) {
        PlayQueue.shared.remove(audiobook)
        playAndPresent(audiobook)
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

    @ToolbarContentBuilder
    private var importToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
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
            // No search field here: the Search tab is the one place that searches the library.
            if viewMode == .list {
                listModeContent
            } else {
                gridModeContent
            }
        }
        .background(TintedBackground(tint: CoverTintCache.tint(for: GlobalAudioManager.shared.currentAudiobook), intensity: 0.85))
        .navigationTitle(NSLocalizedString("Library", comment: "Library navigation title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { importToolbarItem }
        .navigationDestination(item: $audiobookForDetail) { BookDetailView(audiobook: $0, actions: bookActions) }
        .onAppear {
            // Fetch audiobooks when the view first appears
            if audiobookManager.audiobooks.isEmpty && !audiobookManager.isLoadingLibrary {
                audiobookManager.fetchAudiobooks()
            }
        }
        // Backfill: links made before the series lookup existed have no series on them. Each
        // book is asked about once — `seriesChecked` keeps this from running again.
        .task { await HardcoverService.shared.refreshSeries(for: audiobookManager.audiobooks) }
    }

    var body: some View {
        NavigationStack {
            libraryContent
        }
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
        .sheet(item: $audiobookForHardcover) { audiobook in
            HardcoverBookPickerView(audiobook: audiobook)
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
