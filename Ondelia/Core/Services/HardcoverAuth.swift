import CryptoKit
import Foundation

/// Hardcover's OAuth 2.0 flow for a public client: authorization code with PKCE (S256), no
/// client secret. Endpoints come from `hardcover.app/.well-known/oauth-authorization-server`.
///
/// The client id is not a secret — Hardcover hands it out for shipping in the app, and PKCE
/// is what actually binds the code to this launch of the flow.
enum HardcoverAuth {
    static let clientID = "1fbf586d-8c96-48f6-9186-eea32435ddbb"
    static let redirectURI = "ondelia://oauth/hardcover/callback"
    static let callbackScheme = "ondelia"
    /// Search and catalogue reads, the reader's own shelves, and writing progress to them.
    static let scopes = "read:catalog read:library write:library"

    static let authorizeURL = URL(string: "https://hardcover.app/oauth2/authorize")!
    static let tokenURL = URL(string: "https://api.hardcover.app/oauth2/token")!
    static let revokeURL = URL(string: "https://api.hardcover.app/oauth2/revoke")!

    enum Failure: LocalizedError {
        case cancelled
        case stateMismatch
        case denied(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil
            case .stateMismatch:
                return NSLocalizedString(
                    "The sign-in reply did not match this request. Try again.",
                    comment: "Hardcover OAuth state mismatch"
                )
            case .denied(let reason):
                return reason
            case .http(let code):
                return String(
                    format: NSLocalizedString(
                        "Hardcover returned an error (%d).",
                        comment: "Hardcover HTTP failure, %d is the status code"
                    ),
                    code
                )
            }
        }
    }

    /// What the token endpoint hands back. `refresh_token` and `expires_in` are optional in
    /// the spec, so a server that omits them yields a token that is simply never refreshed.
    struct Tokens: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval?
        let tokenType: String?
        /// What Hardcover actually granted, which may be less than what was asked for.
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case scope
        }

        /// Shape of the reply, for the log — never the token itself.
        var summary: String {
            let parts = accessToken.split(separator: ".").count
            return "token_type=\(tokenType ?? "nil") scope=\(scope ?? "nil") "
                + "expires_in=\(expiresIn.map { String(Int($0)) } ?? "nil") "
                + "refresh_token=\(refreshToken == nil ? "no" : "yes") "
                + "access_token=\(accessToken.count) chars, \(parts == 3 ? "JWT" : "opaque")"
        }
    }

    /// One launch of the flow: the URL to open, and the two secrets that tie the reply to it.
    struct Request: Sendable {
        let url: URL
        let verifier: String
        let state: String
    }

    static func makeRequest() -> Request {
        let verifier = randomToken()
        let state = randomToken()
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return Request(url: components.url!, verifier: verifier, state: state)
    }

    /// Trades the code in the callback URL for tokens, after checking it answers `request`.
    static func exchange(callback: URL, for request: Request) async throws -> Tokens {
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        guard value("state") == request.state else { throw Failure.stateMismatch }
        if let error = value("error") {
            throw Failure.denied(value("error_description") ?? error)
        }
        guard let code = value("code") else { throw Failure.denied("missing code") }
        Log.hardcover.info("OAuth callback carried: \(query.map(\.name).joined(separator: ","), privacy: .public)")

        return try await post(tokenURL, form: [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": request.verifier
        ])
    }

    static func refresh(_ refreshToken: String) async throws -> Tokens {
        try await post(tokenURL, form: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ])
    }

    /// Best effort: the local copy is dropped whether or not Hardcover hears about it.
    static func revoke(_ token: String) async {
        var request = URLRequest(url: revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["token": token, "client_id": clientID])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - PKCE

    /// `BASE64URL(SHA256(ASCII(verifier)))`, RFC 7636 §4.2.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Transport

    private static func post(_ url: URL, form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(form)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // An error body carries no secret, only the reason.
            Log.hardcover.error("Token endpoint returned \(http.statusCode, privacy: .public): \(String(decoding: data, as: UTF8.self), privacy: .public)")
            throw Failure.http(http.statusCode)
        }
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        Log.hardcover.info("Token endpoint reply: \(tokens.summary, privacy: .public)")
        return tokens
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // `+` is a literal plus in a query but a space in a form body, so it has to go too.
        let encoded = (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return Data(encoded.utf8)
    }
}
