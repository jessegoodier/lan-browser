import Foundation

/// Host-first address input: a port is never interpreted as a URL scheme.
enum BrowserAddress {
    static func parse(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }
        let candidate: String
        if text.hasPrefix("//") {
            candidate = "http:" + text
        } else if text.contains("://") {
            candidate = text
        } else {
            candidate = "http://" + text
        }
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else { return nil }
        return url
    }
}
