import Foundation
import os
import Security

/// Minimal string store for credentials.
///
/// Not `UserDefaults`: that is a plain plist in the app container and it lands in every
/// unencrypted backup. An API token belongs in the keychain.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.jayet.Isora",
            kSecAttrAccount as String: key
        ]
    }

    static func get(_ key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes `value`, or removes the item when it is nil or empty.
    static func set(_ value: String?, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }

        var item = query(key)
        item[kSecValueData as String] = data
        // Background syncs run with the device locked, so `WhenUnlocked` would fail there.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            // Never the value: this is the Hardcover token.
            Log.hardcover.error("Keychain write failed for \(key, privacy: .public), OSStatus \(status, privacy: .public)")
        }
    }
}
