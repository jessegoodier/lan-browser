import Foundation

/// Which web ports the optional port scan tries. Off unless the user picks and confirms a preset.
enum PortScanPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, standard, common
    var id: String { rawValue }

    static let defaultsKey = "portScanPreset"
    static let confirmedCountKey = "portScanConfirmedCount"

    var ports: [Int] {
        switch self {
        case .off: return []
        case .standard: return [80, 443]
        case .common: return [80, 81, 443, 1880, 3000, 3001, 5000, 5001, 7878, 8000, 8008, 8080, 8081, 8096, 8123, 8443, 8888, 8989, 9000, 9090, 9443, 32400]
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard Web"
        case .common: return "Common Web Apps"
        }
    }

    var summary: String {
        switch self {
        case .off: return "Bonjour only"
        case .standard: return "Ports 80 and 443"
        case .common: return "\(ports.count) ports"
        }
    }
}

/// A block of IPv4 addresses, such as the network the phone is on.
struct IPv4Range: Equatable, Sendable {
    let network: UInt32
    let prefix: Int

    static let maxAddresses = 1024

    init?(cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), (0...32).contains(prefix),
              let address = IPv4Range.number(String(parts[0])) else { return nil }
        self.prefix = prefix
        network = address & IPv4Range.mask(prefix)
    }

    var count: Int { prefix >= 31 ? 0 : (1 << (32 - prefix)) - 2 }
    var first: UInt32 { network + 1 }
    var last: UInt32 { network + UInt32((1 << (32 - prefix)) - 2) }
    var cidr: String { "\(IPv4Range.string(network))/\(prefix)" }
    var description: String { "\(IPv4Range.string(first)) – \(IPv4Range.string(last))" }

    /// Every usable address, leaving out the network and broadcast addresses and the phone itself.
    func hosts(excluding excluded: String? = nil) -> [String] {
        guard count > 0 else { return [] }
        let skip = excluded.flatMap(IPv4Range.number)
        return (first...last).filter { $0 != skip }.map(IPv4Range.string)
    }

    /// The phone’s whole network when it has at most 1,024 addresses, otherwise the /24 around the phone.
    static func scanRange(network: String, deviceIP: String) -> IPv4Range? {
        guard let range = IPv4Range(cidr: network), range.count > 0 else { return nil }
        if range.count <= maxAddresses { return range }
        return IPv4Range(cidr: "\(deviceIP)/24")
    }

    static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }

    static func number(_ address: String) -> UInt32? {
        let octets = address.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        guard octets.count == 4, address.split(separator: ".", omittingEmptySubsequences: false).count == 4 else { return nil }
        return octets.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func string(_ number: UInt32) -> String {
        [24, 16, 8, 0].map { String((number >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }
}

/// What a port scan would do on the current network, shown to the user before it is allowed.
struct PortScanPlan: Identifiable, Equatable, Sendable {
    let preset: PortScanPreset
    let range: IPv4Range
    let deviceIP: String
    var id: String { "\(preset.rawValue)|\(range.cidr)" }

    var addressCount: Int { range.hosts(excluding: deviceIP).count }
    /// Pass 1 tries ports 80 and 443 on every address to find devices that are on.
    var discoveryConnections: Int { addressCount * 2 }

    /// A scan needs (re)confirmation until one is confirmed, and again on a larger network.
    func needsConfirmation(confirmedCount: Int?) -> Bool {
        guard let confirmedCount, confirmedCount > 0 else { return true }
        return addressCount > confirmedCount
    }
}

/// An open port that answered as a web server.
struct WebFinding: Equatable, Sendable {
    let host: String
    let port: Int
    let url: URL
    let status: Int
    let title: String?
    let server: String?
    let location: String?

    var isRedirect: Bool { (300..<400).contains(status) }
}

enum PortScan {
    static let livenessPorts = [80, 443]

    /// Drops answers that aren’t useful pages: 400 Bad Request (the port isn’t a web UI),
    /// redirects to another page that was also found (such as HTTP → HTTPS on the same device),
    /// and the HTTP copy of a page the same device also serves over HTTPS.
    static func collapse(_ findings: [WebFinding]) -> [WebFinding] {
        let found = Set(findings.map { ServiceCatalog.deviceKey($0.url) })
        let useful = findings.filter { finding in
            guard finding.status != 400 else { return false }
            guard finding.isRedirect, let location = finding.location,
                  let target = URL(string: location, relativeTo: finding.url)?.absoluteURL else { return true }
            let targetKey = ServiceCatalog.deviceKey(target)
            return targetKey == ServiceCatalog.deviceKey(finding.url) || !found.contains(targetKey)
        }
        return useful.filter { finding in
            guard finding.url.scheme == "http" else { return true }
            return !useful.contains { other in
                other.host == finding.host && other.url.scheme == "https" && other.port == 443 && finding.port == 80
                    && other.title == finding.title && other.server == finding.server
            }
        }
    }

    /// The row title: the title of the page the redirects end on, else the device’s network
    /// name, else the server software, else the port.
    static func name(for finding: WebFinding, deviceName: String?) -> String {
        if let title = finding.title { return title }
        if let deviceName { return finding.port == 80 || finding.port == 443 ? deviceName : "\(deviceName):\(finding.port)" }
        return finding.server ?? "Web app on port \(finding.port)"
    }

    /// Ports that usually speak HTTPS are tried with TLS first, everything else with plain HTTP first.
    static func prefersHTTPS(port: Int) -> Bool { [443, 5001, 8443, 9443].contains(port) }
}
