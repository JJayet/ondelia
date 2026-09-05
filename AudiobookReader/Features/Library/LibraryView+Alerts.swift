import SwiftUI

extension LibraryView {
    /// Every alert the library raises, funnelled through one `.alert` modifier. Stacking several
    /// on the same view lets SwiftUI drop whichever one it is not currently tracking.
    enum ActiveAlert: Identifiable {
        case rename
        case merge(MergePrompt)
        case importFailed(String)
        case confirmDelete(AudiobookModel)

        var id: String {
            switch self {
            case .rename: return "rename"
            case .merge(let prompt): return prompt.id.uuidString
            case .importFailed: return "importFailed"
            case .confirmDelete(let book): return "delete-\(book.id)"
            }
        }

        var title: String {
            switch self {
            case .rename:
                return NSLocalizedString("Rename Audiobook", comment: "Alert title for renaming")
            case .merge:
                return NSLocalizedString("Merge Audiobooks", comment: "Merge offer alert title")
            case .importFailed:
                return NSLocalizedString("Import Failed", comment: "Import error alert title")
            case .confirmDelete:
                return NSLocalizedString("Delete Audiobook", comment: "Delete confirmation alert title")
            }
        }
    }

    /// A dismissal that did not go through a button still has to answer whatever asked.
    func dismissActiveAlert() {
        switch activeAlert {
        case .merge(let prompt):
            prompt.respond(false)
        case .importFailed:
            audiobookManager.importErrorMessage = nil
        case .rename, .confirmDelete, .none:
            break
        }
        audiobookToRename = nil
        newAudiobookTitle = ""
        activeAlert = nil
    }

    @ViewBuilder
    func alertActions(for alert: ActiveAlert) -> some View {
        switch alert {
        case .rename:
            TextField(NSLocalizedString("New title", comment: "Placeholder for new title"), text: $newAudiobookTitle)
                .onSubmit { commitRename() }

            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}

            Button(NSLocalizedString("Save", comment: "Save button")) { commitRename() }
                .disabled(newAudiobookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        case .merge(let prompt):
            Button(NSLocalizedString("Merge", comment: "Merge the imported books into one")) {
                prompt.respond(true)
            }
            Button(NSLocalizedString("Keep Separate", comment: "Leave the imported books separate"), role: .cancel) {
                prompt.respond(false)
            }

        case .importFailed:
            Button(NSLocalizedString("OK", comment: "Dismiss alert button"), role: .cancel) {}

        case .confirmDelete(let audiobook):
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
            Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    audiobookManager.deleteAudiobook(audiobook)
                }
            }
        }
    }

    @ViewBuilder
    func alertMessage(for alert: ActiveAlert) -> some View {
        switch alert {
        case .rename:
            Text(String(
                format: NSLocalizedString("Enter a new title for '%@'", comment: "Alert message for renaming"),
                audiobookToRename?.title ?? ""
            ))
        case .merge(let prompt):
            Text(String(
                format: NSLocalizedString(
                    "Imported %d audio files from '%@'. Merge them into one audiobook with chapters?",
                    comment: "Merge offer alert message"
                ),
                prompt.bookCount,
                prompt.suggestedTitle
            ))
        case .importFailed(let message):
            Text(message)
        case .confirmDelete(let audiobook):
            Text(String(
                format: NSLocalizedString(
                    "'%@', its progress and its bookmarks will be removed. This cannot be undone.",
                    comment: "Delete confirmation alert message"
                ),
                audiobook.title ?? AudiobookModel.unknownTitle
            ))
        }
    }

    private func commitRename() {
        let trimmed = newAudiobookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let audiobook = audiobookToRename, !trimmed.isEmpty {
            audiobookManager.renameAudiobook(audiobook, newTitle: trimmed)
        }
    }
}
