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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    MiniPlayerBar(namespace: namespace)
                        .onTapGesture { withHapticFeedback { playerRouter.present(book) } }
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
            // The zoom flies the mini player across the screen; Reduce Motion gets the plain
            // cover instead.
            if reduceMotion {
                PlayerSheetView(bookID: presentation.id)
            } else {
                PlayerSheetView(bookID: presentation.id)
                    .navigationTransition(.zoom(sourceID: "MINIPLAYER", in: namespace))
            }
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
            guard url.scheme?.caseInsensitiveCompare("Isora") == .orderedSame else { return }
            switch url.host {
            case "player":
                selectedTab = 1
                if let book = globalAudioManager.currentAudiobook {
                    playerRouter.present(book)
                }
            case "resume":
                // The watch complication's "Resume": the loaded book, else the last one played.
                selectedTab = 1
                Task { @MainActor in
                    guard let book = await PlaybackCommands.loadedBook() else { return }
                    globalAudioManager.startPlayback()
                    playerRouter.present(book)
                }
            default:
                return
            }
        }
        // Handoff from the watch player. Bonus on top of progress sync, so a missing book or a
        // malformed activity is simply ignored.
        .onContinueUserActivity(WatchHandoff.activityType) { activity in
            guard let id = WatchHandoff.bookID(from: activity.userInfo) else { return }
            selectedTab = 1
            var descriptor = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let book = try? SwiftDataController.shared.context.fetch(descriptor).first else { return }
            globalAudioManager.loadAudiobook(book)
            if let position = activity.userInfo?[WatchHandoff.positionKey] as? Double {
                globalAudioManager.seek(to: position)
            }
            playerRouter.present(book)
        }
    }
}

/// The one activity type the watch publishes and the phone continues.
enum WatchHandoff {
    static let activityType = "io.jayet.Isora.listening"
    static let bookIDKey = "bookID"
    static let positionKey = "position"

    static func bookID(from userInfo: [AnyHashable: Any]?) -> UUID? {
        guard let raw = userInfo?[bookIDKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}
