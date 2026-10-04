import SwiftUI

/// The address, port, username and password of a server to sign in to, and the button.
/// `onSignedIn` runs once the server accepted them.
struct AudiobookShelfSignInSections: View {
    var prefill = false
    var onSignedIn: () -> Void = {}

    private let service = AudiobookShelfService.shared
    @State private var server = ""
    /// Optional: replaces any port in the address. Empty means the scheme's default.
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var error: String?

    var body: some View {
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
        .onAppear {
            // The last server signed out of, to sign in again.
            guard prefill, server.isEmpty else { return }
            server = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.server) ?? ""
            username = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.username) ?? ""
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
                await AudiobookShelfCatalog.shared.refresh()
                onSignedIn()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
