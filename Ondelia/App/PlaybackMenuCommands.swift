import SwiftUI

/// The "Playback" menu: the same gestures as on iPad, from a Magic Keyboard or the Mac menu bar.
/// Space and the arrows are unmodified, as in the design; ⌘ variants move a chapter at a time.
struct PlaybackMenuCommands: Commands {
    private var audio: GlobalAudioManager { GlobalAudioManager.shared }

    var body: some Commands {
        CommandMenu(NSLocalizedString("Playback", comment: "Playback menu title")) {
            // Goes through the command path so a cold window with nothing loaded resumes the last book.
            Button(NSLocalizedString("Play / Pause", comment: "Playback menu: toggle")) {
                Task { await PlaybackCommands.perform(.toggle) }
            }
            .keyboardShortcut(.space, modifiers: [])

            Button(NSLocalizedString("Skip Backward", comment: "Skip backward accessibility label")) {
                audio.skipBackward()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button(NSLocalizedString("Skip Forward", comment: "Skip forward accessibility label")) {
                audio.skipForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Divider()

            Button(NSLocalizedString("Previous Chapter", comment: "Previous chapter accessibility label")) {
                audio.skipToPreviousChapter()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button(NSLocalizedString("Next Chapter", comment: "Next chapter accessibility label")) {
                audio.skipToNextChapter()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button(NSLocalizedString("Faster", comment: "Playback menu: next speed step")) {
                PlaybackCommands.stepSpeed(by: 1)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button(NSLocalizedString("Slower", comment: "Playback menu: previous speed step")) {
                PlaybackCommands.stepSpeed(by: -1)
            }
            .keyboardShortcut("[", modifiers: .command)

            Divider()

            Button(NSLocalizedString("Add Bookmark", comment: "Add bookmark button")) {
                PlaybackCommands.addBookmark()
            }
            .keyboardShortcut("b", modifiers: .command)
        }
    }
}
