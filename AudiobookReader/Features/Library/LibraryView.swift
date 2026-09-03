import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct LibraryView: View {
    @StateObject private var audiobookManager: AudiobookManager
    @Environment(\.playerRouter) private var playerRouter
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var statistics = ReadingStatistics()
    @State private var showingStatistics = false
    @State private var audiobookForImagePicker: AudiobookModel?
    @State private var showingRenameAlert = false
    @State private var audiobookToRename: AudiobookModel?
    @State private var newAudiobookTitle = ""
    @State private var viewMode: ViewMode = .list
    @State private var sortOption: SortOption = .lastPlayed
    @State private var filterOption: FilterOption = .all
    @State private var showingImporter = false
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
    
    enum ViewMode: String, CaseIterable {
        case list = "list"
        case grid = "grid"
        
        var displayName: String {
            switch self {
            case .list: return NSLocalizedString("List", comment: "List view mode")
            case .grid: return NSLocalizedString("Grid", comment: "Grid view mode")
            }
        }
        
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case title = "title"
        case author = "author"
        case lastPlayed = "lastPlayed"
        case dateAdded = "dateAdded"
        case progress = "progress"
        
        var displayName: String {
            switch self {
            case .title: return NSLocalizedString("Title", comment: "Sort by title")
            case .author: return NSLocalizedString("Author", comment: "Sort by author")
            case .lastPlayed: return NSLocalizedString("Recently Played", comment: "Sort by recently played")
            case .dateAdded: return NSLocalizedString("Date Added", comment: "Sort by date added")
            case .progress: return NSLocalizedString("Progress", comment: "Sort by progress")
            }
        }
        
        var descriptor: SortDescriptor<AudiobookModel> {
            switch self {
            case .title:
                return SortDescriptor(\AudiobookModel.title)
            case .author:
                return SortDescriptor(\AudiobookModel.author)
            case .lastPlayed:
                return SortDescriptor(\AudiobookModel.lastPlayed, order:.reverse)
            case .dateAdded:
                return SortDescriptor(\AudiobookModel.dateAdded, order:.reverse)
            case .progress:
                return SortDescriptor(\AudiobookModel.currentPosition, order:.reverse)
            }
        }
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "all"
        case inProgress = "inProgress"
        case completed = "completed"
        case notStarted = "notStarted"
        
        var displayName: String {
            switch self {
            case .all: return NSLocalizedString("All", comment: "Filter: all audiobooks")
            case .inProgress: return NSLocalizedString("In Progress", comment: "Filter: books in progress")
            case .completed: return NSLocalizedString("Completed", comment: "Filter: completed books")
            case .notStarted: return NSLocalizedString("Not Started", comment: "Filter: books not started")
            }
        }
        
        func predicate() -> NSPredicate? {
            switch self {
            case .all:
                return nil
            case .inProgress:
                return NSPredicate(format: "currentPosition > 0 AND isFinished == NO")
            case .completed:
                return NSPredicate(format: "isFinished == YES")
            case .notStarted:
                return NSPredicate(format: "currentPosition == 0")
            }
        }
    }
    
    private var filteredAudiobooks: [AudiobookModel] {
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
        // Sort with SortDescriptor for consistency
        let descriptor = sortOption.descriptor
        return filtered.sorted { descriptor.compare($0, $1) == .orderedAscending }
    }

    // MARK: - Actions
    private func playAndPresent(_ audiobook: AudiobookModel) {
        let audio = GlobalAudioManager.shared
        audio.loadAudiobook(audiobook)
        audio.startPlayback()
        playerRouter?.present(audiobook)
    }
    
    private var continueReadingBooks: [AudiobookModel] {
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
    
    // Extracted to help the type-checker
    @ViewBuilder
    private var listModeContent: some View {
        List {
            // Statistics Card
            if !audiobookManager.audiobooks.isEmpty {
                StatisticsCardView(statistics: statistics) { showingStatistics = true }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Continue Reading Section
            if !continueReadingBooks.isEmpty {
                continueReadingSection
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Header with filters
            LibraryHeaderView(
                viewMode: $viewMode,
                sortOption: $sortOption,
                filterOption: $filterOption
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Library Items
            if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                EmptyLibraryView()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 40, leading: 0, bottom: 40, trailing: 0))
            } else {
                if audiobookManager.isImporting {
                    ImportingIndicatorView(manager: audiobookManager)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                ForEach(filteredAudiobooks, id: \.id, content: libraryRow)
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.primaryBackground)
    }

    @ViewBuilder
    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("Continue Reading", comment: "Section title for books in progress"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(continueReadingBooks, id: \.id) { (audiobook: AudiobookModel) in
                        ContinueReadingCardView(audiobook: audiobook) { playAndPresent(audiobook) }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewMode == .list {
                    listModeContent
                } else {
                    // Grid mode - use ScrollView
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Statistics Card
                            if !audiobookManager.audiobooks.isEmpty {
                                StatisticsCardView(statistics: statistics) {
                                    showingStatistics = true
                                }
                                .padding(.horizontal)
                            }
                            
                            // Continue Reading Section
                            if !continueReadingBooks.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(NSLocalizedString("Continue Reading", comment: "Section title for books in progress"))
                                            .font(.title2)
                                            .fontWeight(.bold)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 16) {
                                            ForEach(continueReadingBooks, id: \.id) { audiobook in
                                                ContinueReadingCardView(audiobook: audiobook) { playAndPresent(audiobook) }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Main Library Section
                            VStack(alignment: .leading, spacing: 16) {
                                // Header with filters
                                LibraryHeaderView(
                                    viewMode: $viewMode,
                                    sortOption: $sortOption,
                                    filterOption: $filterOption
                                )
                                .padding(.horizontal)
                                
                                // Content
                                if audiobookManager.audiobooks.isEmpty && !audiobookManager.isImporting {
                                    EmptyLibraryView()
                                    .padding(.horizontal)
                                } else {
                                    VStack(spacing: 16) {
                                        if audiobookManager.isImporting {
                                            ImportingIndicatorView(manager: audiobookManager)
                                                .padding(.horizontal)
                                        }
                                        
                                        LazyVGrid(columns: [
                                            GridItem(.flexible(), spacing: 16),
                                            GridItem(.flexible(), spacing: 16)
                                        ], spacing: 16) {
                                            ForEach(filteredAudiobooks, id: \.id) { audiobook in
                                                AudiobookGridItemView(audiobook: audiobook) { playAndPresent(audiobook) }
                                                .contextMenu {
                                                    Button(NSLocalizedString("Rename", comment: "Rename button")) {
                                                        audiobookToRename = audiobook
                                                        newAudiobookTitle = audiobook.title ?? ""
                                                        showingRenameAlert = true
                                                    }
                                                    
                                                    Button(audiobook.isFinished ? NSLocalizedString("Mark as Unread", comment: "Mark as unread") : NSLocalizedString("Mark as Read", comment: "Mark as read")) {
                                                        if audiobook.isFinished {
                                                            audiobookManager.markAsUnread(audiobook)
                                                        } else {
                                                            audiobookManager.markAsRead(audiobook)
                                                        }
                                                    }
                                                    
                                                    Button(NSLocalizedString("Change Cover Image", comment: "Change cover image button")) {
                                                        audiobookForImagePicker = audiobook
                                                    }
                                                    
                                                    Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                                                        audiobookManager.deleteAudiobook(audiobook)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .background(Color.primaryBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Library", comment: "Library navigation title"))
            .navigationBarTitleDisplayMode(.large)
            .overlay {
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
            .disabled(audiobookManager.isImporting)
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
    }
}

struct StatisticsCardView: View {
    @ObservedObject var statistics: ReadingStatistics
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("This Month", comment: "This month statistics"))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                        
                        Text(statistics.formattedMonthlyProgress)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(String(format: NSLocalizedString("of %@ goal", comment: "Goal progress text"), statistics.formattedMonthlyGoal))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(NSLocalizedString("Total", comment: "Total statistics"))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                        
                        Text(statistics.formattedTotalTime)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(String(format: NSLocalizedString("%d books", comment: "Number of books completed"), statistics.booksCompleted))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }
                
                ProgressView(value: statistics.monthlyGoalProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: 4)
            }
            .padding()
            .glassEffect(in:.rect(cornerRadius: 12))
            
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview("Empty library view") {
    LibraryView()
}

// MARK: - Library Preview with Mock Data
#Preview("Library with mock books") {
    PreviewWrapper {
        SeededLibraryPreview()
    }
}

// MARK: - Importing State Preview
@MainActor
private struct LibraryImportingPreview: View {
    @StateObject private var manager: AudiobookManager
    init() {
        _manager = StateObject(wrappedValue: AudiobookManager())
        manager.isImporting = true
        manager.importQueueTotal = 3
        manager.importQueueCompleted = 1
        manager.currentImportFileName = "Sample.m4b"
    }
    var body: some View {
        LibraryView(audiobookManager: manager)
    }
}

#Preview("Library importing state") {
    LibraryImportingPreview()
}

@MainActor
private struct SeededLibraryPreview: View {
    @Environment(\.modelContext) private var context
    
    var body: some View {
        LibraryView()
            .task {
                // Seed a handful of mock books only once
                let desc = FetchDescriptor<AudiobookModel>()
                let existing = (try? context.fetch(desc)) ?? []
                guard existing.isEmpty else { return }
                
                let samples: [AudiobookModel] = [
                    AudiobookModel.preview(title: "The Art of War", author: "Sun Tzu"),
                    AudiobookModel.preview(title: "1984", author: "George Orwell"),
                    AudiobookModel.preview(title: "Dune", author: "Frank Herbert"),
                    AudiobookModel.preview(title: "The Hobbit", author: "J.R.R. Tolkien"),
                    AudiobookModel.preview(title: "Project Hail Mary", author: "Andy Weir")
                ]
                samples.forEach { context.insert($0) }
                try? context.save()
            }
    }
}


// MARK: - Row Builders
extension LibraryView {
    @ViewBuilder
    private func libraryRow(audiobook: AudiobookModel) -> some View {
        EnhancedAudiobookRowView(audiobook: audiobook) { playAndPresent(audiobook) }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(NSLocalizedString("Delete", comment: "Delete button")) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        audiobookManager.deleteAudiobook(audiobook)
                    }
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                Button(audiobook.isFinished ? NSLocalizedString("Mark Unread", comment: "Mark as unread") : NSLocalizedString("Mark Read", comment: "Mark as read")) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if audiobook.isFinished {
                            audiobookManager.markAsUnread(audiobook)
                        } else {
                            audiobookManager.markAsRead(audiobook)
                        }
                    }
                }
                .tint(audiobook.isFinished ? .orange : .green)
                
                Button(NSLocalizedString("Rename", comment: "Rename button")) {
                    audiobookToRename = audiobook
                    newAudiobookTitle = audiobook.title ?? ""
                    showingRenameAlert = true
                }
                .tint(.blue)
            }
            .contextMenu {
                Button(NSLocalizedString("Rename", comment: "Rename button")) {
                    audiobookToRename = audiobook
                    newAudiobookTitle = audiobook.title ?? ""
                    showingRenameAlert = true
                }
                
                Button(audiobook.isFinished ? NSLocalizedString("Mark as Unread", comment: "Mark as unread") : NSLocalizedString("Mark as Read", comment: "Mark as read")) {
                    if audiobook.isFinished {
                        audiobookManager.markAsUnread(audiobook)
                    } else {
                        audiobookManager.markAsRead(audiobook)
                    }
                }
                
                Button(NSLocalizedString("Change Cover Image", comment: "Change cover image button")) {
                    audiobookForImagePicker = audiobook
                }
            }
    }
}
