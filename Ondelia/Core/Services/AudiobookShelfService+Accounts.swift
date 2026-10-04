import Foundation
import SwiftData

// MARK: - Servers the listener signed in to
extension AudiobookShelfService {
    /// `[AudiobookShelfAccount]` as JSON. Synced by `SettingsSync`; tokens go through iCloud
    /// Keychain instead.
    static let accountsKey = "audiobookshelf.accounts"
    /// The single account's token before several servers; still written for the first server, so
    /// a device on an older version keeps working.
    static let legacyTokenKey = "audiobookshelf.token"

    /// Accounts and their tokens from defaults and the keychain. The first launch after several
    /// servers arrived turns the single account's keys into the first account.
    func reload() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([AudiobookShelfAccount].self, from: data) {
            accounts = decoded
        } else if let legacy = Self.legacyAccount(defaults: defaults), let token = Keychain.get(Self.legacyTokenKey) {
            accounts = [legacy]
            Keychain.set(token, for: legacy.tokenKey, synchronizable: syncsAccount)
            saveAccounts()
        } else {
            accounts = []
        }
        tokens = Dictionary(uniqueKeysWithValues: accounts.compactMap { account in
            Keychain.get(account.tokenKey).map { (account.id, $0) }
        })
    }

    static func legacyAccount(defaults: UserDefaults) -> AudiobookShelfAccount? {
        guard let server = defaults.string(forKey: Defaults.server).flatMap(URL.init(string:)) else { return nil }
        return AudiobookShelfAccount(
            server: server,
            username: defaults.string(forKey: Defaults.username) ?? "",
            library: defaults.string(forKey: Defaults.library)
        )
    }

    /// The first server, which the screens built for one server still read.
    var primary: AudiobookShelfAccount? { accounts.first }
    var server: URL? { primary?.server }
    var username: String? { primary?.username }
    var token: String? { primary.flatMap { tokens[$0.id] } }
    var isSignedIn: Bool { token != nil }

    func token(for account: AudiobookShelfAccount) -> String? { tokens[account.id] }

    var selectedLibrary: String? {
        get { primary?.library }
        set {
            guard !accounts.isEmpty else { return }
            accounts[0].library = newValue
            saveAccounts()
            WatchSyncService.shared.sendServerAccount()
        }
    }

    /// Signs in, adding the server or refreshing its token when it is already known.
    func signIn(server input: String, port: Int? = nil, username: String, password: String) async throws {
        guard let server = AudiobookShelfAPI.serverURL(from: input, port: port) else {
            throw AudiobookShelfAPI.Failure.invalidServer
        }
        let token = try await AudiobookShelfAPI.signIn(server: server, username: username, password: password)
        let account = AudiobookShelfAccount(server: server, username: username)
        Keychain.set(token, for: account.tokenKey, synchronizable: syncsAccount)
        if !accounts.contains(where: { $0.id == account.id }) { accounts.append(account) }
        tokens[account.id] = token
        saveAccounts()
        WatchSyncService.shared.sendServerAccount()
    }

    /// Forgets a server, the first one by default — on every device when synced, since the
    /// token lives in iCloud Keychain. The server keeps the token, which is the legacy per-user
    /// API token and not one this app created, so there is nothing to revoke.
    func signOut(_ account: AudiobookShelfAccount? = nil) {
        guard let account = account ?? primary else { return }
        Keychain.set(nil, for: account.tokenKey)
        accounts.removeAll { $0.id == account.id }
        tokens[account.id] = nil
        saveAccounts()
        WatchSyncService.shared.sendServerAccount()
        AudiobookShelfCatalog.shared.forget()
        AudiobookShelfImages.forget()
    }

    /// Writes the accounts, and mirrors the first into the single-account keys for devices on an
    /// older version. The address and username stay after a sign-out, to fill the form again.
    func saveAccounts() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey)
        if let primary {
            defaults.set(primary.server.absoluteString, forKey: Defaults.server)
            defaults.set(primary.username, forKey: Defaults.username)
            defaults.set(primary.library, forKey: Defaults.library)
        } else {
            defaults.removeObject(forKey: Defaults.library)
        }
        Keychain.set(token, for: Self.legacyTokenKey, synchronizable: syncsAccount)
    }
}

// MARK: - Which server an item lives on
extension AudiobookShelfService {
    /// Links a Library audiobook to a server item and records the item's server. Saving is the
    /// caller's.
    static func insertLink(audiobookID: UUID, itemID: String, serverID: String?, context: ModelContext) {
        context.insert(AudiobookShelfLinkModel(audiobookID: audiobookID, itemID: itemID))
        if let serverID { recordServer(serverID, of: itemID, context: context) }
    }

    static func recordServer(_ serverID: String, of itemID: String, context: ModelContext) {
        let known = FetchDescriptor<AudiobookShelfItemServerModel>(predicate: #Predicate { $0.itemID == itemID })
        guard (try? context.fetchCount(known)) == 0 else { return }
        context.insert(AudiobookShelfItemServerModel(itemID: itemID, serverID: serverID))
    }

    /// Links made before several servers, or by a device on an older version, belong to the
    /// first server: the only one there was. Two devices doing this write the same pairs.
    func backfillItemServers() {
        guard let primary, SwiftDataController.shared.isLoaded else { return }
        let context = SwiftDataController.shared.context
        let known = Set(((try? context.fetch(FetchDescriptor<AudiobookShelfItemServerModel>())) ?? []).map(\.itemID))
        let missing = Set(Self.links().map(\.itemID)).subtracting(known)
        guard !missing.isEmpty else { return }
        for item in missing {
            context.insert(AudiobookShelfItemServerModel(itemID: item, serverID: primary.id))
        }
        SwiftDataController.shared.save()
    }
}
