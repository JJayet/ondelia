import SwiftUI

/// Sign in to an AudiobookShelf server, then browse it to download books into the library.
struct AudiobookShelfSettingsView: View {
    private let service = AudiobookShelfService.shared

    @State private var server = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.server) ?? ""
    /// Optional: replaces any port in the address. Empty means the scheme's default.
    @State private var port = ""
    @State private var username = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.username) ?? ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var error: String?
    @AppStorage(AudiobookShelfCatalog.enabledKey) private var showsInLibrary = false
    @AppStorage(AudiobookShelfService.Defaults.library) private var selectedLibrary = ""
    @AppStorage(AudiobookShelfService.Defaults.tapAction) private var tapAction = AudiobookShelfService.TapAction.stream
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

        if libraries.count > 1 {
            Section {
                Picker(NSLocalizedString("Library", comment: "AudiobookShelf library picker"), selection: $selectedLibrary) {
                    ForEach(libraries) { Text($0.name).tag($0.id) }
                }
                .onChange(of: selectedLibrary) {
                    // Through the service, so the watch follows the new library too.
                    service.selectedLibrary = selectedLibrary
                    Task { await AudiobookShelfCatalog.shared.refresh() }
                }
            } footer: {
                Text(NSLocalizedString(
                    "The server library to browse and download from.",
                    comment: "AudiobookShelf settings: which server library is used"
                ))
            }
        }

        if let account = service.primary {
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

            TextField(
                NSLocalizedString("Port", comment: "AudiobookShelf server port field"),
                text: $port,
                prompt: Text(NSLocalizedString("Port (optional)", comment: "AudiobookShelf server port field placeholder"))
            )
            .accessibilityLabel(NSLocalizedString("Port", comment: "AudiobookShelf server port field"))
            .keyboardType(.numberPad)

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
            .disabled(isSigningIn || server.isEmpty || username.isEmpty || !isPortValid)
        }
    }

    private func loadLibraries() async {
        guard let server = service.server, let token = service.token else { return }
        libraries = (try? await AudiobookShelfAPI.libraries(server: server, token: token)) ?? []
        // Nothing saved yet (or a library gone from the server): show the one the app falls back to.
        if !libraries.contains(where: { $0.id == selectedLibrary }), let first = libraries.first?.id {
            selectedLibrary = first
        }
    }

    private var isPortValid: Bool { port.isEmpty || Int(port).map { (1...65535).contains($0) } == true }

    private func signIn() {
        guard !isSigningIn, !server.isEmpty, !username.isEmpty, isPortValid else { return }
        withHapticFeedback {}
        Task {
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                try await service.signIn(server: server, port: Int(port), username: username, password: password)
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
