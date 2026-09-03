import SwiftUI

struct MainTabView: View {
    private let themeManager = ThemeManager.shared
    private let globalAudioManager = GlobalAudioManager.shared
    @State private var playerRouter = PlayerRouter()
    @State private var selectedTab = 1
    @State private var searchText: String = ""
    @Namespace private var namespace

    var body: some View {
        // Accessory modifier reserves an empty bar even with no content, so apply it only when a book is loaded
        if let book = globalAudioManager.currentAudiobook {
            tabs
                .tabViewBottomAccessory {
                    MiniPlayerBar()
                        .matchedTransitionSource(id: "MINIPLAYER", in: namespace)
                        .onTapGesture { playerRouter.present(book) }
                }
        } else {
            tabs
        }
    }

    @ViewBuilder
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab(value: 0) {
                HomeView()
            } label: {
                Label(NSLocalizedString("Home", comment: "Home tab title"), systemImage: "house.fill")
                    .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.homeTab)
            }

            Tab(value: 1) {
                LibraryView()
            } label: {
                Label(NSLocalizedString("Library", comment: "Library tab title"), systemImage: "books.vertical.fill")
                    .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.libraryTab)
            }

            Tab(value: 2) {
                SettingsView()
            } label: {
                Label(NSLocalizedString("Settings", comment: "Settings tab title"), systemImage: "gear")
                    .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.settingsTab)
            }

            Tab(
                NSLocalizedString("Search", comment: "Search book"),
                systemImage: "magnifyingglass",
                value: 3,
                role: .search
            ) {
                SearchView(query: $searchText)
                    .searchable(text: $searchText)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .tint(themeManager.accentColor.color)
        .environment(\.playerRouter, playerRouter)
        .environment(\.setTabSelection) { index in selectedTab = index }
        .fullScreenCover(item: $playerRouter.presented) { presentation in
            PlayerSheetView(bookID: presentation.id).navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
        }
        .onOpenURL { url in
            // "Open in AudiobookReader" from Files, Mail or AirDrop hands over a file URL.
            guard !url.isFileURL else {
                selectedTab = 1
                AudiobookManager.shared.handleImportRequest(urls: [url])
                return
            }
            guard url.scheme == "audiobookreader", url.host == "player" else { return }
            selectedTab = 1
            if let book = globalAudioManager.currentAudiobook {
                playerRouter.present(book)
            }
        }

    }
}
