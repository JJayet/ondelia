import SwiftUI

struct MainTabView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var globalAudioManager = GlobalAudioManager.shared
    @StateObject private var playerRouter = PlayerRouter()
    @State private var selectedTab = 1
    @State private var searchText: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(
                NSLocalizedString("Home", comment: "Home tab title"),
                systemImage: "house.fill",
                value: 0
            ) {
                HomeView()
            }

            Tab(
                NSLocalizedString("Library", comment: "Library tab title"),
                systemImage: "books.vertical.fill",
                value: 1
            ) {
                // Library Tab
                LibraryView()
            }

            Tab(
                NSLocalizedString("Settings", comment: "Settings tab title"),
                systemImage: "gear",
                value: 2
            ) {
                SettingsView()
            }

            Tab(
                NSLocalizedString("Search", comment: "Search book"),
                systemImage: "magnifyingglass",
                value: 3,
                role: .search
            ) {
                SearchView(query: $searchText)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            // Avoid showing the mini player while the full player sheet is up or dismissing
            if playerRouter.presented == nil, !playerRouter.isDismissing {
                NewMiniPlayerBar()
            }
        }
        .searchable(text: $searchText)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
        .environment(\.theme, themeManager)
        .environment(\.playerRouter, playerRouter)
        .sheet(item: $playerRouter.presented) { presentation in
            PlayerSheetView(bookID: presentation.id)
                .environment(\.playerRouter, playerRouter)
                .presentationDetents([.height(92), .large], selection: $playerRouter.selectedDetent)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
        }

    }
}

#Preview("Empty") {
    MainTabView()
}

#Preview("With books") {
    MainTabView()
        .previewWithMockAudio()
}
