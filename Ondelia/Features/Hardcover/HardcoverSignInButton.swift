import AuthenticationServices
import SwiftUI

/// "Sign in with Hardcover": runs the OAuth flow in the system sheet and stores the result.
///
/// The system session catches the `ondelia://oauth/hardcover/callback` redirect itself, so
/// nothing reaches `onOpenURL`.
struct HardcoverSignInButton: View {
    var onSignedIn: () -> Void = {}

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            withHapticFeedback {}
            Task { await signIn() }
        } label: {
            HStack {
                Label(
                    NSLocalizedString("Sign in with Hardcover", comment: "Hardcover sign-in button"),
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                Spacer()
                if isSigningIn { ProgressView() }
            }
        }
        .disabled(isSigningIn)
        .alert(
            NSLocalizedString("Sign-in Failed", comment: "Hardcover sign-in failure alert title"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "OK button")) { withHapticFeedback {} }
        } message: { message in
            Text(message)
        }
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        let request = HardcoverAuth.makeRequest()
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: request.url,
                callbackURLScheme: HardcoverAuth.callbackScheme
            )
            try await HardcoverService.shared.signIn(callback: callback, for: request)
            onSignedIn()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The reader closed the sheet: not an error worth an alert.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
