import CryptoKit
import Foundation

/// One AudiobookShelf server the listener signed in to. The token is not here: it lives in the
/// keychain under `tokenKey`.
struct AudiobookShelfAccount: Codable, Hashable, Identifiable, Sendable {
    /// Derived from the server and username, so every device gives the same server the same id
    /// without agreeing on it first: links and hidden entries refer to it.
    let id: String
    let server: URL
    let username: String
    /// The server library browsed and blended in; nil until one is picked.
    var library: String?
    var showsInLibrary: Bool

    init(server: URL, username: String, library: String? = nil, showsInLibrary: Bool = true) {
        self.id = Self.id(server: server, username: username)
        self.server = server
        self.username = username
        self.library = library
        self.showsInLibrary = showsInLibrary
    }

    var tokenKey: String { "audiobookshelf.token.\(id)" }

    /// A UUID-shaped hash of the normalised server and the username. Scheme and host compare
    /// without case, a default port counts as none, a trailing slash is dropped.
    static func id(server: URL, username: String) -> String {
        var parts = URLComponents(url: server, resolvingAgainstBaseURL: false) ?? URLComponents()
        let scheme = parts.scheme?.lowercased()
        if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        let key = "\(scheme ?? "")://\(parts.host?.lowercased() ?? ""):\(parts.port.map(String.init) ?? "")\(path)|\(username)"
        var bytes = Array(SHA256.hash(data: Data("audiobookshelf-server:\(key)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 layout, name-based
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString
    }
}
