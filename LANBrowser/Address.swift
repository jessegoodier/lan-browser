import Foundation

/// Host-first address input: a port is never interpreted as a URL scheme.
enum BrowserAddress {
    /// Compare addresses without treating separate pages or protocols as the same bookmark.
    static func bookmarkKey(_ input: String) -> String? {
        guard let url = parse(input), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if parts.port == (parts.scheme == "https" ? 443 : 80) { parts.port = nil }
        if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
        return parts.string
    }

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
