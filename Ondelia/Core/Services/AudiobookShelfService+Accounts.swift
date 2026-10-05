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
        // The accounts can arrive from another device (`SettingsSync`) before this one moved its
        // own single-account sign-in over: that account's token is still under the old key.
        let legacyID = Self.legacyAccount(defaults: defaults)?.id
        tokens = Dictionary(uniqueKeysWithValues: accounts.compactMap { account in
            if let token = Keychain.get(account.tokenKey) { return (account.id, token) }
            guard account.id == legacyID, let token = Keychain.get(Self.legacyTokenKey) else { return nil }
            Keychain.set(token, for: account.tokenKey, synchronizable: syncsAccount)
            return (account.id, token)
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
    /// Signed in to some server.
    var isSignedIn: Bool { !tokens.isEmpty }

    func token(for account: AudiobookShelfAccount) -> String? { tokens[account.id] }

    var selectedLibrary: String? {
        get { primary?.library }
        set { if let primary { setLibrary(newValue, for: primary.id) } }
    }

    func setLibrary(_ library: String?, for accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }), accounts[index].library != library else { return }
        accounts[index].library = library
        saveAccounts()
        WatchSyncService.shared.sendServerAccount()
    }

    func setShowsInLibrary(_ shows: Bool, for accountID: String) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].showsInLibrary = shows
        saveAccounts()
    }

    func account(id: String?) -> AudiobookShelfAccount? {
        id.flatMap { id in accounts.first { $0.id == id } }
    }

    /// The server the browser shows.
    var browsingAccount: AudiobookShelfAccount? { account(id: browsingAccountID) ?? primary }

    /// The server an item lives on: the catalogue knows the shown ones, the records the linked
    /// ones, and the browser the one it shows; the first server otherwise.
    func account(forItem itemID: String) -> AudiobookShelfAccount? {
        account(id: AudiobookShelfCatalog.shared.serverID(forItem: itemID) ?? itemServers[itemID]) ?? browsingAccount
    }

    /// The server a series or collection lives on, the same way.
    func account(forGroup groupID: String) -> AudiobookShelfAccount? {
        account(id: AudiobookShelfCatalog.shared.serverID(forGroup: groupID)) ?? browsingAccount
    }

    /// Where to ask about an item, and with what token.
    func session(forItem itemID: String) -> (server: URL, token: String)? {
        account(forItem: itemID).flatMap { account in token(for: account).map { (account.server, $0) } }
    }

    func session(for account: AudiobookShelfAccount?) -> (server: URL, token: String)? {
        account.flatMap { account in token(for: account).map { (account.server, $0) } }
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
        // A device on an older version reads the first server's token there.
        if account.id == primary?.id { Keychain.set(nil, for: Self.legacyTokenKey) }
        accounts.removeAll { $0.id == account.id }
        tokens[account.id] = nil
        saveAccounts()
        if browsingAccountID == account.id { browsingAccountID = nil }
        WatchSyncService.shared.sendServerAccount()
        AudiobookShelfCatalog.shared.forget(account.id)
        // Covers are cached by item, not by server: keep them while another server is in.
        if accounts.isEmpty { AudiobookShelfImages.forget() }
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
        // Never cleared just because this device has no token for the first server yet: the
        // key may hold the only copy of it, and a delete reaches every device through iCloud.
        if let token {
            Keychain.set(token, for: Self.legacyTokenKey, synchronizable: syncsAccount)
        } else if accounts.isEmpty {
            Keychain.set(nil, for: Self.legacyTokenKey)
        }
    }
}

// MARK: - Which server an item lives on
extension AudiobookShelfService {
    /// Server ids by item, from the records. Memoised per `linksVersion`, like `libraryBooks`.
    var itemServers: [String: String] {
        let version = linksVersion
        if let cached = itemServersCache, cached.version == version { return cached.servers }
        guard SwiftDataController.shared.isLoaded else { return [:] }
        let records = (try? SwiftDataController.shared.context.fetch(FetchDescriptor<AudiobookShelfItemServerModel>())) ?? []
        let servers = Dictionary(records.map { ($0.itemID, $0.serverID) }) { first, _ in first }
        itemServersCache = (version, servers)
        return servers
    }

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
        linksDidChange()
    }
}
