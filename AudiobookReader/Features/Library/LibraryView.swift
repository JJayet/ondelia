import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var audiobookManager = AudiobookManager()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var statistics = ReadingStatistics()
    @State private var searchText = ""
    @State private var selectedAudiobook: Audiobook?
    @State private var showingStatistics = false
    @State private var showingImagePicker = false
    @State private var audiobookForImagePicker: Audiobook?
    @State private var viewMode: ViewMode = .list
    @State private var sortOption: SortOption = .lastPlayed
    @State private var filterOption: FilterOption = .all
    @State private var showingImporter = false
    
    enum ViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
        
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case title = "Title"
        case author = "Author"
        case lastPlayed = "Recently Played"
        case dateAdded = "Date Added"
        case progress = "Progress"
        
        var descriptor: NSSortDescriptor {
            switch self {
            case .title:
                return NSSortDescriptor(keyPath: \Audiobook.title, ascending: true)
            case .author:
                return NSSortDescriptor(keyPath: \Audiobook.author, ascending: true)
            case .lastPlayed:
                return NSSortDescriptor(keyPath: \Audiobook.lastPlayed, ascending: false)
            case .dateAdded:
                return NSSortDescriptor(keyPath: \Audiobook.dateAdded, ascending: false)
            case .progress:
                return NSSortDescriptor(keyPath: \Audiobook.currentPosition, ascending: false)
            }
        }
    }
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case inProgress = "In Progress"
        case completed = "Completed"
        case notStarted = "Not Started"
        
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
    
    private var filteredAudiobooks: [Audiobook] {
        let searchedBooks: [Audiobook]
        if !searchText.isEmpty {
            searchedBooks = audiobookManager.searchAudiobooks(query: searchText)
        } else {
            searchedBooks = audiobookManager.audiobooks
        }

        let filteredBooks: [Audiobook]
        if let predicate = filterOption.predicate() {
            filteredBooks = searchedBooks.filter { book in
                predicate.evaluate(with: book)
            }
        } else {
            filteredBooks = searchedBooks
        }

        let descriptor = sortOption.descriptor
        let sortedBooks = filteredBooks.sorted { book1, book2 in
            descriptor.compare(book1, to: book2) == .orderedAscending
        }

        return sortedBooks
    }
    
    private var continueReadingBooks: [Audiobook] {
        audiobookManager.audiobooks
            .filter { $0.currentPosition > 0 && !$0.isFinished }
            .sorted { $0.lastPlayed ?? Date.distantPast > $1.lastPlayed ?? Date.distantPast }
            .prefix(3)
            .map { $0 }
    }
    
    // MARK: - Import Handler
    private func handleImport(urls: [URL]) {
        for url in urls {
            Task {
                print("📂 Processing import: \(url.lastPathComponent)")
                
                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        print("📁 Importing folder: \(url.lastPathComponent)")
                        await audiobookManager.importAudiobookFolder(from: url)
                    } else {
                        print("🎵 Importing single file: \(url.lastPathComponent)")
                        await audiobookManager.importAudiobook(from: url)
                    }
                } else {
                    print("🎵 Importing file (fallback): \(url.lastPathComponent)")
                    await audiobookManager.importAudiobook(from: url)
                }
                
                await MainActor.run {
                    statistics.addListeningTime(0) // Update streak
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewMode == .list {
                    // List mode - use List for proper swipe actions
                    List {
                        // Statistics Card
                        if !audiobookManager.audiobooks.isEmpty {
                            StatisticsCardView(statistics: statistics) {
                                showingStatistics = true
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        
                        // Continue Reading Section
                        if !continueReadingBooks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Continue Reading")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(continueReadingBooks, id: \.id) { audiobook in
                                            ContinueReadingCardView(audiobook: audiobook) {
                                                selectedAudiobook = audiobook
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
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
                        } else {
                            if audiobookManager.isImporting {
                                ImportingIndicatorView()
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            
                            ForEach(filteredAudiobooks, id: \.id) { audiobook in
                                EnhancedAudiobookRowView(audiobook: audiobook) {
                                    selectedAudiobook = audiobook
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Delete") {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            audiobookManager.deleteAudiobook(audiobook)
                                        }
                                    }
                                    .tint(.red)
                                }
                                .contextMenu {
                                    Button("Change Cover Image") {
                                        audiobookForImagePicker = audiobook
                                        showingImagePicker = true
                                    }
                                    
                                    Button("Delete", role: .destructive) {
                                        audiobookManager.deleteAudiobook(audiobook)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.primaryBackground)
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
                                        Text("Continue Reading")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 16) {
                                            ForEach(continueReadingBooks, id: \.id) { audiobook in
                                                ContinueReadingCardView(audiobook: audiobook) {
                                                    selectedAudiobook = audiobook
                                                }
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
                                            ImportingIndicatorView()
                                                .padding(.horizontal)
                                        }
                                        
                                        LazyVGrid(columns: [
                                            GridItem(.flexible(), spacing: 16),
                                            GridItem(.flexible(), spacing: 16)
                                        ], spacing: 16) {
                                            ForEach(filteredAudiobooks, id: \.id) { audiobook in
                                                AudiobookGridItemView(audiobook: audiobook) {
                                                    selectedAudiobook = audiobook
                                                }
                                                .contextMenu {
                                                    Button("Change Cover Image") {
                                                        audiobookForImagePicker = audiobook
                                                        showingImagePicker = true
                                                    }
                                                    
                                                    Button("Delete", role: .destructive) {
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
            .searchable(text: $searchText, prompt: "Search audiobooks...")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingImporter = true }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .accessibilityLabel("Import Audiobook")
                    .accessibilityIdentifier(AccessibilityIdentifiers.Library.importButton)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.folder, .audio, .mp3],
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
        .accentColor(themeManager.accentColor.color)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .sheet(isPresented: $showingStatistics) {
            StatisticsView(statistics: statistics)
        }
        .fullScreenCover(item: $selectedAudiobook) { audiobook in
            PlayerView(audiobook: audiobook, statistics: statistics)
        }
        .refreshable {
            withAnimation(.easeInOut(duration: 0.5)) {
                audiobookManager.fetchAudiobooks()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            if let audiobook = audiobookForImagePicker {
                ImagePickerView(audiobook: audiobook) { image in
                    audiobookManager.updateCoverImage(for: audiobook, with: image)
                    audiobookForImagePicker = nil
                }
            }
        }
        .onReceive(audiobookManager.$audiobookNeedingCover) { audiobook in
            if let audiobook = audiobook {
                audiobookForImagePicker = audiobook
                showingImagePicker = true
            }
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
                        Text("This Month")
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                        
                        Text(statistics.formattedMonthlyProgress)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("of \(statistics.formattedMonthlyGoal) goal")
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total")
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                        
                        Text(statistics.formattedTotalTime)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("\(statistics.booksCompleted) books")
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }
                
                ProgressView(value: statistics.monthlyGoalProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: 4)
            }
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LibraryView()
}
