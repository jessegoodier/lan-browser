import Foundation
import Security
#if DEBUG
import os
#endif

enum PasswordDiagnostics {
    static func record(_ event: String) {
        #if DEBUG
        Logger(subsystem: "com.jesse.lanbrowser", category: "passwords").info("\(event, privacy: .public)")
        #endif
    }
}

/// Lists contain metadata; secret values are read only for matching AutoFill or explicit reveal.
enum PasswordStore {
    private static let service = "com.jesse.lanbrowser.passwords"

    private static func query(origin: PasswordOrigin, username: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account(origin: origin, username: username),
         kSecAttrSynchronizable as String: false]
    }

    private static func account(origin: PasswordOrigin, username: String) -> String {
        // JSON keeps delimiter characters in user names unambiguous.
        let data = try! JSONEncoder().encode([origin.scheme, origin.host, String(origin.port), username])
        return data.base64EncodedString()
    }

    static func save(_ offer: PasswordOffer) throws {
        let query = query(origin: offer.origin, username: offer.username)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(offer.password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        PasswordDiagnostics.record("Keychain update status: \(status).")
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            PasswordDiagnostics.record("Keychain add status: \(addStatus).")
            try check(addStatus)
        } else {
            try check(status)
        }
        PasswordDiagnostics.record("Password saved.")
    }

    static func list() throws -> [SavedPassword] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrSynchronizable as String: false,
                                   kSecReturnAttributes as String: true,
                                   kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        return ((result as? [[String: Any]]) ?? []).compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = Data(base64Encoded: account),
                  let parts = try? JSONDecoder().decode([String].self, from: data), parts.count == 4 else { return nil }
            let host = parts[1].contains(":") && !parts[1].hasPrefix("[") ? "[\(parts[1])]" : parts[1]
            guard let url = URL(string: "\(parts[0])://\(host):\(parts[2])"),
                  let origin = PasswordOrigin(url) else { return nil }
            return SavedPassword(origin: origin, username: parts[3], modifiedAt: item[kSecAttrModificationDate as String] as? Date ?? .distantPast)
        }.sorted { ($0.origin.label, $0.username) < ($1.origin.label, $1.username) }
    }

    static func password(for saved: SavedPassword) throws -> String {
        var query = query(origin: saved.origin, username: saved.username)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode))
        }
        return value
    }

    static func delete(_ saved: SavedPassword) throws {
        let status = SecItemDelete(query(origin: saved.origin, username: saved.username) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
            ])
        }
    }
}
