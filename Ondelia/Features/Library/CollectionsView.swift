import SwiftUI

/// Every Collection, pushed from the Library strip's See All (design 8b): a scope filter,
/// search, a sort, and the list or grid. Server collections and series with no Collection yet
/// go last, under their own label: nothing of theirs is in the Library.
struct CollectionsView<MenuContent: View>: View {
    let groups: [CollectionGroup]
    let serverOnly: [AudiobookShelfAPI.Series]
    let onOpen: (CollectionGroup) -> Void
    @ViewBuilder let menu: (CollectionGroup) -> MenuContent

    @State private var scope: Scope = .all
    @State private var query = ""
    @AppStorage("collections.sort") private var sort: Sort = .recent
    @AppStorage("collections.viewMode") private var viewMode: LibraryView.ViewMode = .list
    /// The Library's grid density, so a collection is the size of a book beside it.
    @AppStorage("library.gridColumns") private var gridColumns = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Scope: CaseIterable {
        case all, mine, series, server

        var title: String {
            switch self {
            case .all: String(localized: "collections.scope.all", defaultValue: "All", comment: "Collections filter: every collection")
            case .mine: String(localized: "collections.scope.mine", defaultValue: "Mine", comment: "Collections filter: hand-made collections")
            case .series: String(localized: "collections.scope.series", defaultValue: "Series", comment: "Collections filter: Hardcover series")
            case .server: String(localized: "collections.scope.server", defaultValue: "Server", comment: "Collections filter: AudiobookShelf series and collections")
            }
        }
    }

    enum Sort: String, CaseIterable {
        case name, recent, progress

        var title: String {
            switch self {
            case .name: NSLocalizedString("Name", comment: "Collections sort: by name")
            case .recent: NSLocalizedString("Recent", comment: "Collections sort: in progress, then recently played")
            case .progress: NSLocalizedString("Progress", comment: "Collections sort: most listened first")
            }
        }
    }

    @MainActor
    static func scope(of group: CollectionGroup) -> Scope {
        if group.serverSeries != nil { return .server }
        return group.isSeries ? .series : .mine
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedStandardContains(query)
    }

    private var shownGroups: [CollectionGroup] {
        let shown = groups.filter { (scope == .all || Self.scope(of: $0) == scope) && matches($0.name) }
        switch sort {
        case .name: return shown.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent: return shown.sorted(by: CollectionGroup.byRecent)
        case .progress: return shown.sorted { $0.progressFraction > $1.progressFraction }
        }
    }

    private var shownServerOnly: [AudiobookShelfAPI.Series] {
        scope == .all || scope == .server ? serverOnly.filter { matches($0.name) } : []
    }

    private func count(_ scope: Scope) -> Int {
        switch scope {
        case .all: groups.count + serverOnly.count
        case .server: groups.filter { Self.scope(of: $0) == .server }.count + serverOnly.count
        default: groups.filter { Self.scope(of: $0) == scope }.count
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker(NSLocalizedString("Filter", comment: "Search filter picker label"), selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { scope in
                        Text(verbatim: "\(scope.title) \(count(scope))").tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                sortBar.padding(.horizontal, 20).padding(.bottom, 6)

                if shownGroups.isEmpty && shownServerOnly.isEmpty {
                    ContentUnavailableView.search(text: query).padding(.top, 40)
                } else if viewMode == .grid {
                    grid
                } else {
                    list
                }
            }
            .padding(.bottom, 24)
        }
        .background(TintedBackground(tint: CoverTintCache.tint(for: GlobalAudioManager.shared.currentAudiobook), intensity: 0.85))
        .navigationTitle(NSLocalizedString("Collections", comment: "Section title for collections"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Search Collections", comment: "Collections screen: search field prompt")
        )
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            Menu {
                Picker(NSLocalizedString("Sort by", comment: "Search sort picker label"), selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(NSLocalizedString("Sort:", comment: "Collections screen: label before the sort choice"))
                        .foregroundStyle(.secondary)
                    Text(sort.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)

            Picker(NSLocalizedString("View", comment: "Collections screen: list or grid"), selection: $viewMode) {
                ForEach([LibraryView.ViewMode.list, .grid], id: \.self) { mode in
                    Image(systemName: mode.icon).accessibilityLabel(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 76)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewMode)
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(shownGroups) { group in
                Button {
                    withHapticFeedback { onOpen(group) }
                } label: {
                    CollectionRowView(group: group)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(group) }
                Divider()
            }
            serverOnlyLabel
            ForEach(shownServerOnly) { series in
                NavigationLink(value: AudiobookShelfRoute.series(series)) {
                    ServerOnlyCollectionRowView(series: series)
                }
                .buttonStyle(.plain)
                .audiobookShelfDownloadAllMenu(.series(series), name: series.name)
                Divider()
            }
        }
        .padding(.horizontal, 20)
    }

    private var grid: some View {
        let spacing: CGFloat = gridColumns >= 4 ? 10 : 16
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 300 / CGFloat(gridColumns)), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            ForEach(shownGroups) { group in
                CollectionGridItemView(group: group, columns: gridColumns) { onOpen(group) }
                    .contextMenu { menu(group) }
            }
            if !shownServerOnly.isEmpty {
                Section {
                    ForEach(shownServerOnly) { ServerOnlyCollectionGridItemView(series: $0, columns: gridColumns) }
                } header: {
                    serverOnlyLabel
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var serverOnlyLabel: some View {
        if !shownServerOnly.isEmpty {
            Label(
                String(
                    format: NSLocalizedString("On the server, none here · %d", comment: "Collections screen: server series and collections with no book in the Library"),
                    shownServerOnly.count
                ).uppercased(),
                systemImage: "icloud"
            )
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.top, 18)
            .padding(.bottom, 4)
        }
    }
}
