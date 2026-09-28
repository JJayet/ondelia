import SwiftUI

/// Sign in to an AudiobookShelf server, then browse it to download books into the library.
struct AudiobookShelfSettingsView: View {
    private let service = AudiobookShelfService.shared

    @State private var server = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.server) ?? ""
    @State private var username = UserDefaults.standard.string(forKey: AudiobookShelfService.Defaults.username) ?? ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var error: String?

    var body: some View {
        List {
            if service.isSignedIn {
                signedInSections
            } else {
                signInSections
            }
        }
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
            NavigationLink {
                AudiobookShelfLibraryView()
            } label: {
                Label(
                    NSLocalizedString("Browse Library", comment: "AudiobookShelf: open the server library"),
                    systemImage: "books.vertical"
                )
                .foregroundStyle(Color.primaryText)
            }
        } footer: {
            Text(NSLocalizedString(
                "Downloaded books are imported into your library and play offline.",
                comment: "AudiobookShelf browse section footer"
            ))
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
