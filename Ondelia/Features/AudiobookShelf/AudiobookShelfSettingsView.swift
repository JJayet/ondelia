import SwiftUI

/// Sign in to an AudiobookShelf server, then browse it to download books into the library.
struct AudiobookShelfSettingsView: View {
    private let service = AudiobookShelfService.shared

    @State private var server = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.server) ?? ""
    @State private var username = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.username) ?? ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var error: String?
    @AppStorage(AudiobookShelfCatalog.enabledKey) private var showsInLibrary = false
    @AppStorage(AudiobookShelfService.Defaults.library) private var selectedLibrary = ""
    @State private var libraries: [AudiobookShelfAPI.Library] = []

    var body: some View {
        List {
            if service.isSignedIn {
                signedInSections
            } else {
                signInSections
            }
        }
        .task(id: service.isSignedIn) { await loadLibraries() }
        .navigationTitle("AudiobookShelf")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
    }

    @ViewBuilder private var signedInSections: some View {
        Section {
            Label(service.server?.host() ?? "", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.primaryText)
            if let name = service.username {
                Label(name, systemImage: "person")
                    .foregroundStyle(Color.primaryText)
            }
        } header: {
            Text(NSLocalizedString("Account", comment: "AudiobookShelf settings section: account"))
        }

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

        // The server shelf's library menu, here while the Library has no shelf to carry it.
        if showsInLibrary, libraries.count > 1 {
            Section {
                Picker(NSLocalizedString("Library", comment: "AudiobookShelf library picker"), selection: $selectedLibrary) {
                    ForEach(libraries) { Text($0.name).tag($0.id) }
                }
                .onChange(of: selectedLibrary) {
                    Task { await AudiobookShelfCatalog.shared.refresh() }
                }
            } footer: {
                Text(NSLocalizedString(
                    "The server library whose audiobooks appear in Library.",
                    comment: "AudiobookShelf settings: which server library is blended in"
                ))
            }
        }

        Section {
            Button(role: .destructive) {
                withHapticFeedback { service.signOut() }
            } label: {
                Text(NSLocalizedString("Sign Out", comment: "AudiobookShelf sign-out button"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var signInSections: some View {
        Section {
            TextField(
                NSLocalizedString("Server Address", comment: "AudiobookShelf server URL field"),
                text: $server,
                prompt: Text(verbatim: "https://abs.example.com")
            )
            // With a prompt, the title no longer reaches VoiceOver: only the example URL did.
            .accessibilityLabel(NSLocalizedString("Server Address", comment: "AudiobookShelf server URL field"))
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField(NSLocalizedString("Username", comment: "AudiobookShelf username field"), text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField(NSLocalizedString("Password", comment: "AudiobookShelf password field"), text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
        } header: {
            Text(NSLocalizedString("Server", comment: "AudiobookShelf settings section: server"))
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else {
                Text(NSLocalizedString(
                    "Sign in to your AudiobookShelf server to download its books.",
                    comment: "AudiobookShelf sign-in section footer"
                ))
            }
        }

        Section {
            Button(action: signIn) {
                HStack {
                    Text(NSLocalizedString("Sign In", comment: "AudiobookShelf sign-in button"))
                    if isSigningIn {
                        Spacer()
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isSigningIn || server.isEmpty || username.isEmpty)
        }
    }

    private func loadLibraries() async {
        guard let server = service.server, let token = service.token else { return }
        libraries = (try? await AudiobookShelfAPI.libraries(server: server, token: token)) ?? []
    }

    private func signIn() {
        guard !isSigningIn, !server.isEmpty, !username.isEmpty else { return }
        withHapticFeedback {}
        Task {
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                try await service.signIn(server: server, username: username, password: password)
                password = ""
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#Preview("AudiobookShelf Settings") {
    NavigationStack {
        AudiobookShelfSettingsView()
    }
}
