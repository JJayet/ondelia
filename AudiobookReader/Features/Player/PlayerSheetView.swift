import SwiftUI
import SwiftData

struct PlayerSheetView: View {
    let bookID: UUID
    @State private var book: AudiobookModel?
    
    var body: some View {
        Group {
            if let book {
                PlayerView(audiobook: book)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(NSLocalizedString("Loading…", comment: "Loading player content"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .task { await loadBook() }
            }
        }
    }
    
    @MainActor
    private func loadBook() async {
        let context = SwiftDataController.shared.context
        let descriptor = FetchDescriptor<AudiobookModel>(
            predicate: #Predicate<AudiobookModel> { $0.id == bookID }
        )
        do {
            let result = try context.fetch(descriptor)
            self.book = result.first
        } catch {
            Log.ui.error("❌ PlayerSheetView: Failed to fetch audiobook by ID: \(error)")
        }
    }
}
