import CoreSpotlight
import SwiftData
import SwiftUI
import UIKit

struct MainTabView: View {
    private let themeManager = ThemeManager.shared
    private let globalAudioManager = GlobalAudioManager.shared
    private let statistics = ReadingStatistics.shared
    private let audiobookManager = AudiobookManager.shared
    @State private var playerRouter = PlayerRouter()
    @State private var selectedTab = "library"
    @State private var searchText: String = ""
    @State private var showingImporter = false
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false

    var body: some View {
        // Applied once here: sheets and covers presented from the tabs inherit both, so no
        // other view sets them.
        themedTabs
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .tint(themeManager.accentColor.color)
            .overlay(alignment: .top) {
                if let milestone = statistics.newlyUnlocked {
                    MilestoneToast(milestone: milestone) {
                        withAnimation { statistics.newlyUnlocked = nil }
                    }
                }
            }
            .animation(.spring(duration: 0.4), value: statistics.newlyUnlocked)
            .fullScreenCover(isPresented: Binding(
                get: { !onboardingCompleted && !OnboardingView.suppressed },
                set: { if !$0 { onboardingCompleted = true } }
            )) {
                OnboardingView { onboardingCompleted = true }
                    .preferredColorScheme(themeManager.currentTheme.colorScheme)
                    .tint(themeManager.accentColor.color)
            }
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
            // No TabSection: on iPad's floating tab bar a section collapses to one entry that
            // only opens the sidebar, which hid Statistics.
            // Sidebar only (iPad landscape, Mac): the player as a pane, design 6a. Built in
            // regular width only: `.sidebarOnly` still surfaced the tab on the iPhone. No
            // badge: on the floating tab bar it would be a red dot.
            if horizontalSizeClass == .regular {
                Tab(value: "inProgress") {
                    NowPlayingView()
                } label: {
                    Label(NSLocalizedString("In Progress", comment: "Filter: books in progress"), systemImage: "play.fill")
                }
                .tabPlacement(.sidebarOnly)
            }

            Tab(value: "library") {
                LibraryView()
            } label: {
                Label(NSLocalizedString("Library", comment: "Library tab title"), systemImage: "books.vertical.fill")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.libraryTab)

            Tab(value: "statistics") {
                StatisticsView(statistics: statistics)
            } label: {
                Label(NSLocalizedString("Statistics", comment: "Statistics view title"), systemImage: "chart.bar.fill")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.statisticsTab)

            Tab(value: "settings") {
                SettingsView()
            } label: {
                Label(NSLocalizedString("Settings", comment: "Settings tab title"), systemImage: "gear")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.settingsTab)

            Tab(
                NSLocalizedString("Search", comment: "Search book"),
                systemImage: "magnifyingglass",
                value: "search",
                role: .search
            ) {
                SearchView(query: $searchText)
                    .searchable(text: $searchText)
            }

            // One sidebar entry per collection, opening straight onto it.
            if horizontalSizeClass == .regular {
            TabSection(NSLocalizedString("Collections", comment: "Section title for collections")) {
                ForEach(audiobookManager.collections, id: \.id) { collection in
                    // A server series or collection counts the server's books, not only the
                    // Library's: one joined book of sixteen reads as 16.
                    let server = AudiobookShelfCatalog.shared.seriesByCollection[collection.id]
                    Tab(value: "collection:\(collection.id.uuidString)") {
                        LibraryView(collection: collection)
                    } label: {
                        Label(collection.name, systemImage: Self.sidebarIcon(collection, server: server))
                    }
                    .badge(max(collection.bookIDs.count, server?.books?.count ?? 0))
                }
            }
            .tabPlacement(.sidebarOnly)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // No collapse button above the sidebar: the design keeps it always open. TabView has
        // no API for it (`.toolbar(removing: .sidebarToggle)` is ignored), so the button is
        // found by its identifier and hidden. The sidebar is rebuilt whenever it reopens, so
        // this runs on a slow tick rather than once.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if horizontalSizeClass == .regular { Self.hideSidebarToggle() }
        }
        // The design's sidebar (iPad landscape, Mac): the app's name up top, import at the
        // bottom, and the Hardcover sync state in the footer.
        .tabViewSidebarHeader {
            Text(verbatim: "Ondelia")
                .font(.system(size: 25, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tabViewSidebarBottomBar {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Text(verbatim: "Hardcover ·")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    HardcoverStatusLine()
                }
                Button {
                    showingImporter = true
                } label: {
                    Label(NSLocalizedString("Import Files", comment: "Sidebar: import audiobook files"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 13.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            // The bar sits flush on the window edge on the Mac; without this the import row is cut.
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .sheet(isPresented: $showingImporter) {
            DocumentPickerView { urls in
                showingImporter = false
                AudiobookManager.shared.handleImportRequest(urls: urls)
            }
            .ignoresSafeArea()
        }
        .environment(\.playerRouter, playerRouter)
        // Regular width shows the player as the Now Playing pane instead of a cover.
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            playerRouter.showPane = sizeClass == .regular ? { selectedTab = "inProgress" } : nil
            if sizeClass == .regular, playerRouter.presented != nil {
                playerRouter.presented = nil
                selectedTab = "inProgress"
            }
        }
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
            selectedTab = "library"
            var descriptor = FetchDescriptor<AudiobookModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let book = try? SwiftDataController.shared.context.fetch(descriptor).first else { return }
            globalAudioManager.loadAudiobook(book)
            playerRouter.present(book)
        }
        .onOpenURL { url in
            // "Open in Ondelia" from Files, Mail or AirDrop hands over a file URL.
            guard !url.isFileURL else {
                selectedTab = "library"
                AudiobookManager.shared.handleImportRequest(urls: [url])
                return
            }
            // "Isora" kept so links made before the rename to Ondelia still open.
            guard let scheme = url.scheme?.lowercased(), ["ondelia", "isora"].contains(scheme) else { return }
            switch url.host {
            case "player":
                selectedTab = "library"
                if let book = globalAudioManager.currentAudiobook {
                    playerRouter.present(book)
                }
            case "resume":
                // The watch complication's "Resume": the loaded book, else the last one played.
                selectedTab = "library"
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
            selectedTab = "library"
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

extension MainTabView {
    /// A series, Hardcover's or a server's, gets the shelf of books; a server collection the
    /// stack its Library card shows; a hand-made collection the folder.
    static func sidebarIcon(_ collection: CollectionModel, server: AudiobookShelfAPI.Series?) -> String {
        if let server { return server.isServerCollection ? "rectangle.stack" : "books.vertical" }
        return collection.isSeries ? "books.vertical" : "folder"
    }

    // ponytail: view-tree walk by accessibility identifier; drop when TabView offers a switch.
    static func hideSidebarToggle() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { hide(in: window) }
        }
    }

    private static func hide(in view: UIView) {
        if view.accessibilityIdentifier == "ToggleSidebar" {
            // The platter container draws the glass; fade it rather than hide it, since a
            // hidden view leaves its stack and shifted the sidebar up for a frame on the Mac.
            // Bounded: a miss touches only the button itself, never the window.
            var node: UIView? = view
            while let current = node, !"\(type(of: current))".hasPrefix("NavigationBarPlatterContainer") {
                node = current.superview
            }
            let target = node ?? view
            target.alpha = 0
            target.isUserInteractionEnabled = false
            return
        }
        view.subviews.forEach(hide(in:))
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
