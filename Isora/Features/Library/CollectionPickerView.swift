import SwiftUI

/// Puts one or several books into hand-made collections: tick the ones they belong in, or
/// type a name to start a new one holding them.
struct CollectionPickerView: View {
    let books: [AudiobookModel]
    @Environment(\.dismiss) private var dismiss
    private let manager = AudiobookManager.shared
    @State private var newName = ""

    private var manual: [CollectionModel] {
        manager.collections
            .filter { !$0.isSeries }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("New Collection", comment: "New collection section")) {
                    HStack {
                        TextField(NSLocalizedString("Collection name", comment: "New collection name placeholder"), text: $newName)
                            .onSubmit(create)
                        Button(NSLocalizedString("Create", comment: "Create button"), action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !manual.isEmpty {
                    Section(NSLocalizedString("Collections", comment: "Existing collections section")) {
                        ForEach(manual, id: \.id) { collection in
                            Button {
                                withHapticFeedback { toggle(collection) }
                            } label: {
                                HStack {
                                    Text(collection.name).foregroundStyle(.primary)
                                    Spacer()
                                    if containsAll(collection) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Add to Collection", comment: "Collection picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { withHapticFeedback { dismiss() } }
                }
            }
        }
    }

    private func containsAll(_ collection: CollectionModel) -> Bool {
        let ids = Set(collection.bookIDs)
        return books.allSatisfy { ids.contains($0.id) }
    }

    private func toggle(_ collection: CollectionModel) {
        if containsAll(collection) {
            for book in books { manager.remove(book, from: collection) }
        } else {
            manager.add(books, to: collection)
        }
    }

    private func create() {
        guard manager.createCollection(name: newName, books: books) != nil else { return }
        withHapticFeedback { dismiss() }
    }
}
