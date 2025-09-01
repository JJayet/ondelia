import SwiftUI

struct MainTabView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var globalAudioManager = GlobalAudioManager.shared
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
            MiniPlayerView()
        }
        .searchable(text: $searchText)
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .accentColor(themeManager.accentColor.color)
        .environment(\.theme, themeManager)

    }
}

#Preview("Empty") {
    MainTabView()
}

#Preview("With books") {
    MainTabView()
        .previewWithMockAudio()
}
