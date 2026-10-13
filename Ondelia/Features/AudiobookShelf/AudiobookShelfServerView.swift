import SwiftUI

/// One signed-in server: its account, whether its audiobooks are shown, which server library,
/// what is hidden, and signing out.
struct AudiobookShelfServerView: View {
    let accountID: String
    /// The right half of the server list around the fold (design 15a): titled in the list, and
    /// signing out stays here, at the bottom, rather than going back.
    var besideList = false

    private let service = AudiobookShelfService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var libraries: [AudiobookShelfAPI.Library] = []

    private var account: AudiobookShelfAccount? { service.account(id: accountID) }

    var body: some View {
        if besideList {
            list.safeAreaInset(edge: .bottom) {
                if let account {
                    signOutButton(account)
                        .buttonStyle(.glass)
                        .tint(.red)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        } else {
            list
                .navigationTitle(account?.displayName ?? "AudiobookShelf")
                .navigationBarTitleDisplayMode(.inline)
                .background(TintedBackground(intensity: 0.6))
        }
    }

    private var list: some View {
        List {
            if let account {
                if besideList {
                    Section {} header: { FoldPaneTitle(account.displayName) }
                }
                sections(for: account)
            }
        }
        .task { await loadLibraries() }
        .scrollContentBackground(.hidden)
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
            NavigationLink {
                AudiobookShelfHiddenView(account: account)
            } label: {
                LabeledContent(
                    NSLocalizedString("Hidden & Shown", comment: "AudiobookShelf settings: hide or show server entries"),
                    value: hiddenCount(on: account)
                )
            }
        } footer: {
            Text(NSLocalizedString(
                "Hidden books, series and authors stay on the server and appear nowhere in Ondelia.",
                comment: "AudiobookShelf settings footer: hidden entries"
            ))
        }

        if !besideList {
            Section { signOutButton(account) }
        }
    }

    private func signOutButton(_ account: AudiobookShelfAccount) -> some View {
        Button(role: .destructive) {
            withHapticFeedback { service.signOut(account) }
            if !besideList { dismiss() }
        } label: {
            Text(NSLocalizedString("Sign Out", comment: "AudiobookShelf sign-out button"))
                .frame(maxWidth: .infinity)
                .frame(minHeight: besideList ? 36 : nil)
        }
    }

    /// Everything hidden on this server, for the row that leads to it.
    private func hiddenCount(on account: AudiobookShelfAccount) -> String {
        let hidden = AudiobookShelfHidden.shared
        let count = HiddenServerEntryModel.Kind.allCases.reduce(0) { $0 + hidden.hidden($1, on: account.id).count }
        return count == 0 ? "" : String(format: NSLocalizedString("%d hidden", comment: "AudiobookShelf settings: how many server entries are hidden"), count)
    }

    private func loadLibraries() async {
        guard let (server, token) = service.session(for: account) else { return }
        libraries = (try? await AudiobookShelfAPI.libraries(server: server, token: token)) ?? []
    }
}
