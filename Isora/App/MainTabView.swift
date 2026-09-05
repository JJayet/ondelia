import CoreSpotlight
import SwiftData
import SwiftUI

struct MainTabView: View {
    private let themeManager = ThemeManager.shared
    private let globalAudioManager = GlobalAudioManager.shared
    @State private var playerRouter = PlayerRouter()
    @State private var selectedTab = 1
    @State private var searchText: String = ""
    @Namespace private var namespace

    var body: some View {
        // Applied once here: sheets and covers presented from the tabs inherit both, so no
        // other view sets them.
        themedTabs
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .tint(themeManager.accentColor.color)
    }

    @ViewBuilder
    private var themedTabs: some View {
        // Accessory modifier reserves an empty bar even with no content, so apply it only when
        // there is a mini player to put in it — a stopped book leaves one behind.
        if let book = globalAudioManager.currentAudiobook, globalAudioManager.showMiniPlayer {
            tabs
                .tabViewBottomAccessory {
                    MiniPlayerBar()
                        .matchedTransitionSource(id: "MINIPLAYER", in: namespace)
                        .onTapGesture { playerRouter.present(book) }
                        // The tap gesture is invisible to VoiceOver, which reaches the bar as a
                        // container of buttons and would otherwise have no way to expand it.
                        .accessibilityAction(
                            named: Text(NSLocalizedString("Open Player", comment: "Accessibility action: expand the mini player"))
                        ) {
                            playerRouter.present(book)
                        }
                }
        } else {
            tabs
        }
    }

    /// Note for UI tests: a tab bar button surfaces only its localized label, whether the
    /// identifier is set here on the `Tab` or inside its `Label` — so the tests match on the
    /// label and launch the app in English.
    @ViewBuilder
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab(value: 1) {
                LibraryView()
            } label: {
                Label(NSLocalizedString("Library", comment: "Library tab title"), systemImage: "books.vertical.fill")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.libraryTab)

            Tab(value: 2) {
                SettingsView()
            } label: {
                Label(NSLocalizedString("Settings", comment: "Settings tab title"), systemImage: "gear")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.settingsTab)

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
        .environment(\.playerRouter, playerRouter)
        .fullScreenCover(item: $playerRouter.presented) { presentation in
            PlayerSheetView(bookID: presentation.id).navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
        }
        // A tapped Spotlight result names the book by its UUID.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: identifier) else { return }
            selectedTab = 1
            var descriptor = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let book = try? SwiftDataController.shared.context.fetch(descriptor).first else { return }
            globalAudioManager.loadAudiobook(book)
            playerRouter.present(book)
        }
        .onOpenURL { url in
            // "Open in Isora" from Files, Mail or AirDrop hands over a file URL.
            guard !url.isFileURL else {
                selectedTab = 1
                AudiobookManager.shared.handleImportRequest(urls: [url])
                return
            }
            guard url.scheme == "Isora", url.host == "player" else { return }
            selectedTab = 1
            if let book = globalAudioManager.currentAudiobook {
                playerRouter.present(book)
            }
        }

    }
}
