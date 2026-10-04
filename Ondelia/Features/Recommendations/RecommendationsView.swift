import SwiftUI

/// Up to three audiobooks to listen to next, each under what kind of pick it is, each with why. Picked on device (`Recommender`).
struct RecommendationsView: View {
    let history: [AudiobookModel]
    let collections: [CollectionModel]
    let server: [AudiobookShelfAPI.Item]

    @State private var picks: [Recommender.Pick] = []
    @State private var failure: String?
    @State private var loading = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.audiobookShelfPlay) private var play

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(NSLocalizedString("Finding your next listen…", comment: "Recommendations: picking"))
                            .foregroundStyle(.secondary)
                    }
                } else if let failure {
                    ContentUnavailableView(
                        NSLocalizedString("No Picks", comment: "Recommendations: none could be made"),
                        systemImage: "sparkles",
                        description: Text(failure)
                    )
                } else {
                    ForEach(picks) { pick in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(title(pick.kind))
                            row(pick.candidate)
                            Text(pick.reason)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(NSLocalizedString("Recommended for You", comment: "Recommendations screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                    .accessibilityLabel(NSLocalizedString("Other Picks", comment: "Recommendations: ask again"))
                }
            }
        }
        .task { await load() }
    }

    private func title(_ kind: Recommender.Pick.Kind) -> String {
        switch kind {
        case .resume: NSLocalizedString("Continue", comment: "Recommendations: the book in progress")
        case .nextInSeries: NSLocalizedString("Next in a Series", comment: "Recommendations: the next volume of a series")
        case .different: NSLocalizedString("Something Different", comment: "Recommendations: the model's pick away from the usual")
        }
    }

    @ViewBuilder
    private func row(_ candidate: Recommender.Candidate) -> some View {
        switch candidate.source {
        case .server(let item):
            AudiobookShelfBookRow(item: item)
        case .book(let book):
            EnhancedAudiobookRowView(audiobook: book) {
                dismiss()
                play?.run(book)
            }
        }
    }

    private func load() async {
        loading = true
        failure = nil
        defer { loading = false }
        do {
            picks = try await Recommender.recommend(books: history, collections: collections, server: server)
            if picks.isEmpty {
                failure = NSLocalizedString("Nothing stood out this time. Try again.", comment: "Recommendations: the model picked nothing usable")
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// The Library's way in: opens the picks in a sheet, reading the history and the server books
/// only then.
struct RecommendationsButton: View {
    let history: () -> [AudiobookModel]
    let server: () -> [AudiobookShelfAPI.Item]
    @State private var shown = false

    var body: some View {
        Button {
            withHapticFeedback { shown = true }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
        }
        .accessibilityLabel(NSLocalizedString("Recommended for You", comment: "Recommendations screen title"))
        .sheet(isPresented: $shown) {
            RecommendationsView(history: history(), collections: AudiobookManager.shared.collections, server: server())
        }
    }
}
