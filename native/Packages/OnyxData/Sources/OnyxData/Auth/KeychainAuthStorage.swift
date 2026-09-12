import Foundation
import Security
import Supabase

/// Supabase session storage backed by the iOS Keychain.
///
/// ── WHY THE KEYCHAIN, AND NOT WHAT THE WEB APP DOES ─────────────────────────
/// The web app persisted its session in `localStorage` with a
/// preferences-plugin (UserDefaults) mirror, and `SecureStore.swift` — the
/// Keychain plugin that would have fixed it — was written and then left
/// unregistered, on the reasoning that a single-user app can afford one extra
/// tap. That reasoning stops applying here: `UserDefaults` is not encrypted at
/// rest and a refresh token is a long-lived credential. The native app has no
/// reason to repeat the compromise, because there is no WKWebView storage
/// container to be compatible with.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
///   · *AfterFirstUnlock* so a background refresh still works with the phone
///     locked — the widget and background tasks run in that state;
///   · *ThisDeviceOnly* so the token is excluded from iCloud Keychain and from
///     encrypted backups. A session should not travel to another device.
///
/// NOTE: no `kSecAttrAccessGroup`. Keychain sharing groups need a paid Apple
/// Developer Program membership, exactly like App Groups. On a free personal
/// team this must stay a private, per-target keychain item — which also means
/// the widget extension cannot read it, and that is why the snapshot path
/// stays a separate opaque token for now.
public final class KeychainAuthStorage: AuthLocalStorage, Sendable {
    private let service: String

    public init(service: String = "app.onyx.health.michael.native.auth") {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func store(key: String, value: Data) throws {
        // Delete-then-add rather than add-then-update-on-duplicate: the update
        // path has to spell out the mutable attributes separately, and getting
        // that list wrong silently keeps the OLD accessibility class.
        SecItemDelete(query(key) as CFDictionary)

        var attributes = query(key)
        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
    }

    public func retrieve(key: String) throws -> Data? {
        var attributes = query(key)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)

        // A missing session is an ordinary state — first launch, or after a sign
        // out. It must not throw, or the app cannot start.
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
        return item as? Data
    }

    public func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpected(status)
        }
    }
}

public enum KeychainError: Error, CustomStringConvertible {
    case unexpected(OSStatus)

    public var description: String {
        switch self {
        case .unexpected(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain error \(status): \(message)"
        }
    }
}
