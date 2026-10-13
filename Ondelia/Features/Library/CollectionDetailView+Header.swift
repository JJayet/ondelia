import SwiftUI

// MARK: - Kind label and menu
extension CollectionDetailView {
    var kindLabel: some View {
        Text((group.isSeries
            ? NSLocalizedString("Series", comment: "Collection detail header: a Hardcover series")
            : NSLocalizedString("Collection", comment: "Collection detail header: hand-made")).uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    var moreMenu: some View {
        Menu { menuItems } label: { Image(systemName: "ellipsis") }
            .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
            .accessibilityLabel(NSLocalizedString("More", comment: "Book actions menu"))
    }

    @ViewBuilder
    var menuItems: some View {
        Menu {
            ForEach(CollectionSort.allCases.filter { $0 != .seriesPosition || group.isSeries }, id: \.rawValue) { sort in
                Button { withHapticFeedback { manager.setSort(sort, for: collection) } } label: {
                    if collection.sort == sort {
                        Label(sort.displayName, systemImage: "checkmark")
                    } else {
                        Text(sort.displayName)
                    }
                }
            }
        } label: {
            Label(NSLocalizedString("Sort by", comment: "Search sort picker label"), systemImage: "arrow.up.arrow.down")
        }
        if !group.isSeries {
            Button { onRename(collection) } label: {
                Label(NSLocalizedString("Rename", comment: "Rename button"), systemImage: "pencil")
            }
        }
        Button(role: .destructive) { onDelete(collection) } label: {
            Label(NSLocalizedString("Delete Collection", comment: "Delete a collection, keeping its books"), systemImage: "trash")
        }
        .tint(.red)
    }
}
