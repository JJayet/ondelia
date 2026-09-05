import SwiftUI

struct LibraryHeaderView: View {
    @Binding var viewMode: LibraryView.ViewMode
    @Binding var sortOption: LibraryView.SortOption
    @Binding var filterOption: LibraryView.FilterOption

    var body: some View {
        HStack(spacing: 9) {
            Menu {
                ForEach(LibraryView.FilterOption.allCases, id: \.rawValue) { option in
                    Button(option.displayName) {
                        withAnimation(.easeInOut(duration: 0.2)) { filterOption = option }
                    }
                }
            } label: {
                chip(filterOption.displayName, tinted: true)
            }

            Menu {
                ForEach(LibraryView.SortOption.allCases, id: \.rawValue) { option in
                    Button(option.displayName) {
                        withAnimation(.easeInOut(duration: 0.2)) { sortOption = option }
                    }
                }
            } label: {
                chip(sortOption.displayName, tinted: false)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.sortButton)

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewMode = viewMode == .list ? .grid : .list
                }
            } label: {
                Image(systemName: viewMode.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(
                viewMode == .list
                    ? NSLocalizedString("Show Grid", comment: "Switch library to grid")
                    : NSLocalizedString("Show List", comment: "Switch library to list")
            )
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
