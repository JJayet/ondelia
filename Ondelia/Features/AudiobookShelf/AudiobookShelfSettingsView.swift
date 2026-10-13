import SwiftUI

/// Sign in to AudiobookShelf servers, then browse them to stream or download books.
struct AudiobookShelfSettingsView: View {
    private let service = AudiobookShelfService.shared

    @AppStorage(AudiobookShelfCatalog.enabledKey) private var showsInLibrary = false
    @AppStorage(AudiobookShelfService.Defaults.tapAction) private var tapAction = AudiobookShelfService.TapAction.stream
    @Environment(\.isFoldSplit) private var isFoldSplit

    /// Around the fold, what the right half shows.
    private enum Pick: Hashable { case server(String), add }
    @State private var picked: Pick?

    /// The tapped row while it exists, else the first server, else the sign-in form.
    private var current: Pick {
        if case .server(let id) = picked, service.account(id: id) == nil { return firstPick }
        return picked ?? firstPick
    }

    private var firstPick: Pick { service.accounts.first.map { .server($0.id) } ?? .add }

    var body: some View {
        FoldSplit {
            // iPhone Duo (design 15a): the servers and the settings they share on the left,
            // the picked server, or the sign-in form, on the right.
            List {
                serversSection
                if !service.accounts.isEmpty { settingsSections }
            }
        } secondary: {
            switch current {
            case .server(let id):
                AudiobookShelfServerView(accountID: id, besideList: true).id(id)
            case .add:
                List {
                    Section {} header: { FoldPaneTitle(NSLocalizedString("Add Server", comment: "AudiobookShelf settings: sign in to another server")) }
                    AudiobookShelfSignInSections(prefill: service.accounts.isEmpty) {
                        picked = service.accounts.last.map { .server($0.id) }
                    }
                }
            }
        } fallback: {
            List {
                if service.accounts.isEmpty {
                    AudiobookShelfSignInSections(prefill: true)
                } else {
                    serversSection
                    settingsSections
                }
            }
        }
        .navigationTitle("AudiobookShelf")
        .navigationBarTitleDisplayMode(isFoldSplit ? .large : .inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
    }

    private var serversSection: some View {
        Section {
            ForEach(service.accounts) { account in
                if isFoldSplit {
                    Button { withHapticFeedback { picked = .server(account.id) } } label: { serverLabel(account) }
                        .listRowBackground(pickedBackground(current == .server(account.id)))
                } else {
                    NavigationLink {
                        AudiobookShelfServerView(accountID: account.id)
                    } label: {
                        serverLabel(account)
                    }
                }
            }
            if isFoldSplit {
                Button { withHapticFeedback { picked = .add } } label: { addServerLabel }
                    .listRowBackground(pickedBackground(current == .add))
            } else {
                NavigationLink {
                    AddServerView()
                } label: {
                    addServerLabel
                }
            }
        } header: {
            Text(NSLocalizedString("Servers", comment: "AudiobookShelf settings section: signed-in servers"))
        }
    }

    private func serverLabel(_ account: AudiobookShelfAccount) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(account.displayName, systemImage: service.token(for: account) == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(Color.primaryText)
            Text(account.username)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var addServerLabel: some View {
        Label(NSLocalizedString("Add Server", comment: "AudiobookShelf settings: sign in to another server"), systemImage: "plus")
    }

    /// The row whose detail the right half shows.
    private func pickedBackground(_ isPicked: Bool) -> Color? {
        isPicked ? Color.accentColor.opacity(0.12) : nil
    }

    @ViewBuilder private var settingsSections: some View {
        Section {
            Toggle(
                NSLocalizedString("Show server audiobooks in Library", comment: "AudiobookShelf setting: blend server books into the Library"),
                isOn: $showsInLibrary
            )
        } header: {
            Text(NSLocalizedString("Library", comment: "AudiobookShelf library picker"))
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
