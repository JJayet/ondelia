import SwiftUI

struct LibraryHeaderView: View {
    @Binding var viewMode: LibraryView.ViewMode
    @Binding var sortOption: LibraryView.SortOption
    @Binding var filterOption: LibraryView.FilterOption

    var body: some View {
        HStack(spacing: 16) {
            // Filter Options
            Menu {
                ForEach(LibraryView.FilterOption.allCases, id: \.rawValue) {
                    option in
                    Button(option.displayName) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterOption = option
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterOption.displayName)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.caption)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }

            // Sort Options
            Menu {
                ForEach(LibraryView.SortOption.allCases, id: \.rawValue) {
                    option in
                    Button(option.displayName) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sortOption = option
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.displayName)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.caption)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.sortButton)

            Spacer()

            // View Mode Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewMode = viewMode == .list ? .grid : .list
                }
            } label: {
                Image(systemName: viewMode.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .accessibilityLabel(
                viewMode == .list
                    ? NSLocalizedString("Show Grid", comment: "Switch library to grid")
                    : NSLocalizedString("Show List", comment: "Switch library to list")
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Library.viewModeToggle)
        }
    }
}
