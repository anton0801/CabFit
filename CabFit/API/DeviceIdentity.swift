//
//  DeviceIdentity.swift
//  CabFit
//
//  The credential this device authenticates with.
//

import Foundation
import Security

/// A random identifier and a 256-bit secret, generated on this device and kept in the
/// Keychain.
///
/// Deliberately NOT the advertising identifier. IDFA is handed to third parties by
/// design, so it is not a secret and cannot gate access to someone's projects; it is all
/// zeros for every user who declines App Tracking Transparency, which would collapse
/// them into one shared account; and the user can reset it at will, which would orphan
/// their data. `identifierForVendor` has the same "not a secret" problem. A locally
/// generated secret has none of these failure modes and needs no permission prompt.
struct DeviceIdentity: Equatable {
    let uid: String       // UUID, the public half
    let secret: String    // 64 hex chars, never leaves the Keychain except to authenticate
}

enum DeviceIdentityStore {

    private static let service = "online.cabfit-app.identity"
    private static let account = "device"

    /// The identity for this install, creating one on first launch.
    ///
    /// Stored with `kSecAttrAccessibleAfterFirstUnlock` (without `ThisDeviceOnly`) so an
    /// encrypted device backup carries it to a new phone — which is the whole point of
    /// having a server copy. It is readable in the background after the first unlock,
    /// which background sync needs.
    static func loadOrCreate() throws -> DeviceIdentity {
        // A read that fails is treated the same as "nothing stored yet": the only useful
        // next move is to try writing a fresh credential. Propagating the read error
        // instead would leave the app retrying a lookup that can never start succeeding.
        // `try?` flattens the double optional here: a thrown error and a missing item
        // both arrive as nil, which is exactly the handling we want.
        if let identity = try? load() {
            return identity
        }
        let fresh = DeviceIdentity(uid: UUID().uuidString.lowercased(),
                                   secret: randomHex(32))
        try save(fresh)
        return fresh
    }

    static func load() throws -> DeviceIdentity? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &item) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        query.removeAll()

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError(status: status)
        }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            // Unreadable blob: treat it as absent rather than wedging the app forever.
            return nil
        }
        return DeviceIdentity(uid: stored.uid, secret: stored.secret)
    }

    static func save(_ identity: DeviceIdentity) throws {
        let data = try JSONEncoder().encode(Stored(uid: identity.uid, secret: identity.secret))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound { throw KeychainError(status: updateStatus) }

        var insert = query
        insert.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    /// Only used when the server rejects the credential outright, so the app can start
    /// over rather than retry a secret that will never be accepted again.
    static func reset() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private struct Stored: Codable {
        let uid: String
        let secret: String
    }

    private static func randomHex(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // SecRandom should not fail; if it ever does, a lower-quality source still
            // beats a predictable constant.
            bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "Keychain error: \(message)"
        }
        return "Keychain error \(status)."
    }
}

// MARK: - Session tokens

/// Access and refresh tokens. Kept in the Keychain rather than UserDefaults: a token is
/// a bearer credential, and UserDefaults is a plist in the app container.
struct SessionTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
    /// Refresh slightly early so a request does not race the expiry.
    var needsRefresh: Bool { Date().addingTimeInterval(60) >= expiresAt }
}

enum SessionStore {
    private static let service = "online.cabfit-app.session"
    private static let account = "tokens"

    static func load() -> SessionTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &item) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SessionTokens.self, from: data)
    }

    static func save(_ tokens: SessionTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
