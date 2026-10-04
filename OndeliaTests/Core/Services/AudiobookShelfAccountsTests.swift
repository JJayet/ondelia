import Foundation
import Testing
@testable import Isora

@MainActor
@Suite("AudiobookShelf accounts", .serialized)
struct AudiobookShelfAccountsTests {
    @Test("Accounts synced from another device pick up this device's single-account token")
    func syncedAccountsAdoptLegacyToken() throws {
        let defaults = UserDefaults.standard
        let service = AudiobookShelfService.shared
        let account = AudiobookShelfAccount(server: try #require(URL(string: "https://shelf.example")), username: "reader")
        let keys = [AudiobookShelfService.accountsKey, AudiobookShelfService.Defaults.server, AudiobookShelfService.Defaults.username]
        let saved = keys.map { defaults.object(forKey: $0) }
        let savedLegacy = Keychain.get(AudiobookShelfService.legacyTokenKey)
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
            Keychain.set(savedLegacy, for: AudiobookShelfService.legacyTokenKey)
            Keychain.set(nil, for: account.tokenKey)
            service.reload()
        }

        // This device signed in before several servers; the account list arrives already migrated.
        defaults.set(account.server.absoluteString, forKey: AudiobookShelfService.Defaults.server)
        defaults.set(account.username, forKey: AudiobookShelfService.Defaults.username)
        Keychain.set("token", for: AudiobookShelfService.legacyTokenKey)
        Keychain.set(nil, for: account.tokenKey)
        defaults.set(try JSONEncoder().encode([account]), forKey: AudiobookShelfService.accountsKey)

        service.reload()

        #expect(service.token(for: account) == "token")
        #expect(Keychain.get(account.tokenKey) == "token")
    }
}
