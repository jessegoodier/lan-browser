import Foundation

struct PasswordOrigin: Hashable {
    let scheme: String
    let host: String
    let port: Int

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        port = url.port ?? (scheme == "https" ? 443 : 80)
    }

    var label: String {
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(authority):\(port)"
    }
}

enum PasswordPolicy {
    static let enabledKey = "offerToSavePasswords"
    static let autofillKey = "autofillSavedPasswords"

    static func autofillEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: autofillKey) as? Bool ?? true
    }

    static func accountToFill(_ accounts: [SavedPassword], origin: PasswordOrigin, username: String) -> SavedPassword? {
        accounts.filter { $0.origin == origin && (username.isEmpty || $0.username == username) }
            .sorted {
                if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
                return $0.username < $1.username
            }.first
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}

struct PasswordOffer: Identifiable {
    let id = UUID()
    let tabID: UUID
    let origin: PasswordOrigin
    let username: String
    let password: String
}

struct SavedPassword: Identifiable {
    let origin: PasswordOrigin
    let username: String
    let modifiedAt: Date
    var id: String { origin.label + "/" + username }

    init(origin: PasswordOrigin, username: String, modifiedAt: Date = .distantPast) {
        self.origin = origin
        self.username = username
        self.modifiedAt = modifiedAt
    }
}
