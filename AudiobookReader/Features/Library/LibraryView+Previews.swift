import SwiftUI
import SwiftData

#Preview("Empty library view") {
    LibraryView()
}

// MARK: - Library Preview with Mock Data
#Preview("Library with mock books") {
    PreviewWrapper {
        SeededLibraryPreview()
    }
}

// MARK: - Importing State Preview
@MainActor
private struct LibraryImportingPreview: View {
    @StateObject private var manager: AudiobookManager
    init() {
        _manager = StateObject(wrappedValue: AudiobookManager())
        manager.isImporting = true
        manager.importQueueTotal = 3
        manager.importQueueCompleted = 1
        manager.currentImportFileName = "Sample.m4b"
    }
    var body: some View {
        LibraryView(audiobookManager: manager)
    }
}

#Preview("Library importing state") {
    LibraryImportingPreview()
}

@MainActor
private struct SeededLibraryPreview: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        LibraryView()
            .task {
                // Seed a handful of mock books only once
                let desc = FetchDescriptor<AudiobookModel>()
                let existing = (try? context.fetch(desc)) ?? []
                guard existing.isEmpty else { return }

                let samples: [AudiobookModel] = [
                    AudiobookModel.preview(title: "The Art of War", author: "Sun Tzu"),
                    AudiobookModel.preview(title: "1984", author: "George Orwell"),
                    AudiobookModel.preview(title: "Dune", author: "Frank Herbert"),
                    AudiobookModel.preview(title: "The Hobbit", author: "J.R.R. Tolkien"),
                    AudiobookModel.preview(title: "Project Hail Mary", author: "Andy Weir")
                ]
                samples.forEach { context.insert($0) }
                try? context.save()
            }
    }
}

#Preview() {
    LibraryView()
        .previewWithMockAudio()
}
