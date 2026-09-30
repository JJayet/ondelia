import SwiftUI

/// The library's import button: straight to the file picker, or, once signed in to
/// AudiobookShelf, a menu offering the server shelf as well.
struct ImportMenu<Label: View>: View {
    let onFiles: () -> Void
    let onAudiobookShelf: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        if AudiobookShelfService.shared.isSignedIn {
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
