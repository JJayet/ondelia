import SwiftUI

/// One signed-in server: its account, whether its audiobooks are shown, which server library,
/// what is hidden, and signing out.
struct AudiobookShelfServerView: View {
    let accountID: String

    private let service = AudiobookShelfService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var libraries: [AudiobookShelfAPI.Library] = []

    private var account: AudiobookShelfAccount? { service.account(id: accountID) }

    var body: some View {
        List {
            if let account {
                sections(for: account)
            }
        }
        .task { await loadLibraries() }
        .navigationTitle(account?.displayName ?? "AudiobookShelf")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
    }

    @ViewBuilder
    private func sections(for account: AudiobookShelfAccount) -> some View {
        Section {
            Label(account.server.absoluteString, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.primaryText)
            Label(account.username, systemImage: "person")
                .foregroundStyle(Color.primaryText)
        } header: {
            Text(NSLocalizedString("Account", comment: "AudiobookShelf settings section: account"))
        }

        Section {
            Toggle(
                NSLocalizedString("Show in Library", comment: "AudiobookShelf server setting: blend this server's books into the Library"),
                isOn: Binding(
                    get: { account.showsInLibrary },
                    set: { shows in
                        service.setShowsInLibrary(shows, for: account.id)
                        Task { await AudiobookShelfCatalog.shared.refresh() }
                    }
                )
            )
            if libraries.count > 1 {
                Picker(
                    NSLocalizedString("Library", comment: "AudiobookShelf library picker"),
                    selection: Binding(
                        get: { account.library ?? libraries.first?.id ?? "" },
                        set: { library in
                            service.setLibrary(library, for: account.id)
                            Task { await AudiobookShelfCatalog.shared.refresh() }
                        }
                    )
                ) {
                    ForEach(libraries) { Text($0.name).tag($0.id) }
                }
            }
        } footer: {
            if libraries.count > 1 {
                Text(NSLocalizedString(
                    "The server library to browse and download from.",
                    comment: "AudiobookShelf settings: which server library is used"
                ))
            }
        }

        Section {
            NavigationLink(NSLocalizedString("Hidden & Shown", comment: "AudiobookShelf settings: hide or show server entries")) {
                AudiobookShelfHiddenView(account: account)
            }
        } footer: {
            Text(NSLocalizedString(
                "Hidden books, series and authors stay on the server and appear nowhere in Ondelia.",
                comment: "AudiobookShelf settings footer: hidden entries"
            ))
        }

        Section {
            Button(role: .destructive) {
                withHapticFeedback { service.signOut(account) }
                dismiss()
            } label: {
                Text(NSLocalizedString("Sign Out", comment: "AudiobookShelf sign-out button"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func loadLibraries() async {
        guard let (server, token) = service.session(for: account) else { return }
        libraries = (try? await AudiobookShelfAPI.libraries(server: server, token: token)) ?? []
    }
}
