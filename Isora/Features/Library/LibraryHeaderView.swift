import SwiftUI

struct LibraryHeaderView: View {
    @Binding var viewMode: LibraryView.ViewMode
    @Binding var sortOption: LibraryView.SortOption
    @Binding var filterOption: LibraryView.FilterOption
    @Binding var gridColumns: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gridColumnChoices = [2, 3, 4]

    var body: some View {
        HStack(spacing: 9) {
            Menu {
                ForEach(LibraryView.FilterOption.allCases, id: \.rawValue) { option in
                    Button(option.displayName) {
                        withHapticFeedback {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { filterOption = option }
                        }
                    }
                }
            } label: {
                chip(filterOption.displayName, tinted: true)
            }
            // The chip's own text is the choice, so the menu needs a name of its own.
            .accessibilityLabel(NSLocalizedString("Filter", comment: "Search filter picker label"))
            .accessibilityValue(filterOption.displayName)

            Menu {
                ForEach(LibraryView.SortOption.allCases, id: \.rawValue) { option in
                    Button(option.displayName) {
                        withHapticFeedback {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { sortOption = option }
                        }
                    }
                }
            } label: {
                chip(sortOption.displayName, tinted: false)
            }
            .accessibilityLabel(NSLocalizedString("Sort by", comment: "Search sort picker label"))
            .accessibilityValue(sortOption.displayName)
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.sortButton)

            Spacer(minLength: 0)

            Menu {
                Section(NSLocalizedString("Books per row", comment: "Grid density menu title")) {
                    ForEach(Self.gridColumnChoices, id: \.self) { count in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                gridColumns = count
                                if viewMode == .list { viewMode = .grid }
                            }
                        } label: {
                            HStack {
                                Text(verbatim: "\(count)")
                                if gridColumns == count {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: viewMode.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            } primaryAction: {
                withHapticFeedback {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        viewMode = viewMode == .list ? .grid : .list
                    }
                }
            }
            .accessibilityLabel(
                viewMode == .list
                    ? NSLocalizedString("Show Grid", comment: "Switch library to grid")
                    : NSLocalizedString("Show List", comment: "Switch library to list")
            )
            .accessibilityValue(viewMode == .grid ? Text(verbatim: "\(gridColumns)") : Text(verbatim: ""))
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.viewModeToggle)
        }
    }

    /// Filter and sort read as glass pills, the tinted one carrying the active filter.
    private func chip(_ title: String, tinted: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(0.6)
        }
        .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .glassPill(height: 34, tinted: tinted)
    }
}
