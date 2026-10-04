import SwiftUI

/// Sign in to AudiobookShelf servers, then browse them to stream or download books.
struct AudiobookShelfSettingsView: View {
    private let service = AudiobookShelfService.shared

    @AppStorage(AudiobookShelfCatalog.enabledKey) private var showsInLibrary = false
    @AppStorage(AudiobookShelfService.Defaults.tapAction) private var tapAction = AudiobookShelfService.TapAction.stream

    var body: some View {
        List {
            if service.accounts.isEmpty {
                AudiobookShelfSignInSections(prefill: true)
            } else {
                serversSection
                settingsSections
            }
        }
        .navigationTitle("AudiobookShelf")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
    }

    private var serversSection: some View {
        Section {
            ForEach(service.accounts) { account in
                NavigationLink {
                    AudiobookShelfServerView(accountID: account.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(account.displayName, systemImage: service.token(for: account) == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(Color.primaryText)
                        Text(account.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink {
                AddServerView()
            } label: {
                Label(NSLocalizedString("Add Server", comment: "AudiobookShelf settings: sign in to another server"), systemImage: "plus")
            }
        } header: {
            Text(NSLocalizedString("Servers", comment: "AudiobookShelf settings section: signed-in servers"))
        }
    }

    @ViewBuilder private var settingsSections: some View {
        Section {
            Toggle(
                NSLocalizedString("Show server audiobooks in Library", comment: "AudiobookShelf setting: blend server books into the Library"),
                isOn: $showsInLibrary
            )
        } footer: {
            Text(showsInLibrary
                ? NSLocalizedString(
                    "Every book of your server library appears in Library, Search and Collections. Tap one to stream it; long-press to download it.",
                    comment: "AudiobookShelf settings footer, server books shown in the Library"
                )
                : NSLocalizedString(
                    "Your server's books are in Library, under AudiobookShelf. Tap one to download it; downloaded books play offline.",
                    comment: "AudiobookShelf settings: where the server books are"
                ))
        }

        Section {
            Picker(NSLocalizedString("Tap Action", comment: "AudiobookShelf setting: what tapping a server book does"), selection: $tapAction) {
                Text(NSLocalizedString("Stream", comment: "AudiobookShelf: stream item button"))
                    .tag(AudiobookShelfService.TapAction.stream)
                Text(NSLocalizedString("Download", comment: "AudiobookShelf: download item button"))
                    .tag(AudiobookShelfService.TapAction.download)
            }
        } footer: {
            Text(NSLocalizedString(
                "What tapping a book that is not on this device does. A long press offers the other.",
                comment: "AudiobookShelf settings footer: tap action"
            ))
        }
    }
}

/// Signs in to one more server, then goes back to the list.
private struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List { AudiobookShelfSignInSections { dismiss() } }
            .navigationTitle(NSLocalizedString("Add Server", comment: "AudiobookShelf settings: sign in to another server"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(TintedBackground(intensity: 0.6))
    }
}

#Preview("AudiobookShelf Settings") {
    NavigationStack {
        AudiobookShelfSettingsView()
    }
}
