import SwiftUI

/// The "In Progress" sidebar entry on iPad and Mac: the player as a pane beside the sidebar,
/// with the tab accessory as its transport. Nothing loaded yet: the last book played, else an
/// invitation to pick one.
struct NowPlayingView: View {
    private let audio = GlobalAudioManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if let book = audio.currentAudiobook {
                    PlayerView(openedBook: book, embedded: true)
                        .id(book.id)
                } else {
                    ContentUnavailableView(
                        NSLocalizedString("Nothing playing", comment: "Now Playing pane: no book loaded"),
                        systemImage: "play.circle",
                        description: Text(NSLocalizedString(
                            "Pick a book in the library to start listening.",
                            comment: "Now Playing pane: hint when no book is loaded"
                        ))
                    )
                    .background(TintedBackground(intensity: 0.6))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { if audio.currentAudiobook == nil { await PlaybackCommands.loadedBook() } }
    }
}
