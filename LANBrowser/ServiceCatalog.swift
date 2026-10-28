import Foundation

/// A web app advertised over Bonjour, as found by the most recent scan.
struct DiscoveredService: Identifiable, Codable, Equatable, Sendable {
    let name: String
    let type: String
    let url: URL
    /// The IP the host name resolved to, shown beside the device name.
    var address: String?
    var id: String { url.absoluteString }
}

enum ServiceCatalog {
    /// Must match NSBonjourServices in Info.plist; Scripts/check.sh enforces this.
    static let types = [
        "_http._tcp",
        "_https._tcp",
        "_home-assistant._tcp",
        "_plexmediasvr._tcp",
        "_ipp._tcp",
        "_ipps._tcp",
        "_octoprint._tcp",
        "_esphomelib._tcp",
        "_wled._tcp"
    ]

    private static let generic: Set<String> = ["_http._tcp", "_https._tcp"]

    /// The page to open for a resolved service. Printers and ESPHome advertise a non-web
    /// port, so their admin pages are on the default HTTP/HTTPS port instead.
    static func url(type: String, host: String, port: Int, txt: [String: String] = [:]) -> URL? {
        var components = URLComponents()
        components.scheme = ["_https._tcp", "_ipps._tcp"].contains(type) ? "https" : "http"
        components.host = host
        switch type {
        case "_ipp._tcp", "_ipps._tcp", "_esphomelib._tcp":
            break
        case "_plexmediasvr._tcp":
            components.port = port
            components.path = "/web"
        default:
            if port != (components.scheme == "https" ? 443 : 80) { components.port = port }
            if ["_http._tcp", "_https._tcp", "_octoprint._tcp"].contains(type), let path = txt["path"], !path.isEmpty {
                components.path = path.hasPrefix("/") ? path : "/" + path
            }
        }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    /// Identifies one web server on one device, regardless of which service type advertised it.
    static func deviceKey(_ url: URL) -> String {
        endpointKey(host: url.host ?? "", port: port(of: url))
    }

    static func endpointKey(host: String, port: Int) -> String { "\(DeviceStore.key(host)):\(port)" }

    static func port(of url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }

    /// The URL’s host and port, plus the same port at the IP the host was last seen at.
    static func endpointKeys(for url: URL, address: String?) -> [String] {
        [url.host, address].compactMap { $0 }.map { endpointKey(host: $0, port: port(of: url)) }
    }

    /// True when a bookmark already points at this web server: the same port on the same
    /// host name or IP. `bookmarked` holds `endpointKeys` for every bookmark.
    static func isBookmarked(_ service: DiscoveredService, bookmarked: Set<String>) -> Bool {
        endpointKeys(for: service.url, address: service.address).contains(where: bookmarked.contains)
    }

    /// One row per host and port, preferring a specific service type over plain HTTP.
    static func merged(_ services: [DiscoveredService]) -> [DiscoveredService] {
        var best: [String: DiscoveredService] = [:]
        for service in services {
            let key = deviceKey(service.url)
            if let existing = best[key], !generic.contains(existing.type) || generic.contains(service.type) { continue }
            best[key] = service
        }
        return best.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Private, link-local and mDNS addresses, plus single-label names resolved by the router.
    static func isLocalHost(_ host: String) -> Bool {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if name == "localhost" || name.hasSuffix(".local") { return true }
        let octets = name.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        if octets.count == 4, octets.allSatisfy({ $0.map { (0...255).contains($0) } ?? false }) {
            let a = octets[0]!, b = octets[1]!
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        if name.contains(":") {
            return name == "::1" || name.hasPrefix("fe8") || name.hasPrefix("fe9") || name.hasPrefix("fea") || name.hasPrefix("feb")
                || name.hasPrefix("fc") || name.hasPrefix("fd")
        }
        return !name.contains(".")
    }
}
