import SwiftUI

/// The library's import button: straight to the file picker, or, once signed in to
/// AudiobookShelf, a menu offering the server shelf as well — unless the server's audiobooks
/// are already in the Library, where there is no shelf to go to.
struct ImportMenu<Label: View>: View {
    let onFiles: () -> Void
    let onAudiobookShelf: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        if AudiobookShelfService.shared.isSignedIn, !AudiobookShelfCatalog.shared.isEnabled {
            Menu {
                Button(action: onFiles) {
                    SwiftUI.Label(
                        NSLocalizedString("Files", comment: "Import menu: pick files from the Files app"),
                        systemImage: "folder"
                    )
                }
                Button(action: onAudiobookShelf) {
                    SwiftUI.Label("AudiobookShelf", systemImage: "server.rack")
                }
            } label: {
                label
            }
            .simultaneousGesture(TapGesture().onEnded { withHapticFeedback {} })
        } else {
            Button(action: onFiles) { label }
        }
    }
}
