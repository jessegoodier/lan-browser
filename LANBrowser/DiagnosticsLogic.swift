import Foundation

enum ConnectionFailure: Error, Equatable, Sendable {
    case noNetwork
    case permissionDenied
    case nameNotFound
    case refused
    case timedOut
    case unreachable
    case secureConnectionFailed
    case noHTTPResponse
    case httpError(Int)
}

enum DiagnosticKind: Int, CaseIterable, Sendable {
    case network, permission, dns, port, http

    var title: String {
        switch self {
        case .network: return "Network"
        case .permission: return "Local Network Access"
        case .dns: return "Name Lookup"
        case .port: return "Port"
        case .http: return "Web Server"
        }
    }
}

enum DiagnosticStatus: Equatable, Sendable {
    case pending, running, passed, warning, failed, skipped
}

struct DiagnosticStep: Identifiable, Equatable, Sendable {
    let kind: DiagnosticKind
    var status: DiagnosticStatus = .pending
    var detail = ""
    var advice: String?
    var id: DiagnosticKind { kind }
}

/// Where a URL actually connects: host, port and whether TLS is used.
struct DiagnosticTarget: Equatable, Sendable {
    let host: String
    let port: Int
    let secure: Bool
    let path: String

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        self.host = host
        secure = scheme == "https"
        port = url.port ?? (secure ? 443 : 80)
        path = url.path.isEmpty ? "/" : url.path
    }

    var isLocal: Bool { ServiceCatalog.isLocalHost(host) }
    var hostHeader: String {
        let name = host.contains(":") ? "[\(host)]" : host
        return port == (secure ? 443 : 80) ? name : "\(name):\(port)"
    }
}

enum DiagnosticsText {
    static func advice(for failure: ConnectionFailure, target: DiagnosticTarget) -> String {
        switch failure {
        case .noNetwork:
            return "This iPhone isn’t connected to a network. Turn on Wi-Fi and join the same network as your device."
        case .permissionDenied:
            return "LAN Browser isn’t allowed to reach devices on your network. Turn on Settings › Privacy & Security › Local Network › LAN Browser. If iOS just asked, tap Allow, then Retry Checks."
        case .nameNotFound:
            if target.host.lowercased().hasSuffix(".local") {
                return "No device answered to this .local name. Check the spelling, that the device is on, and that it’s on the same Wi-Fi network. Its IP address may work instead."
            }
            return "This name couldn’t be found. Check the spelling, or use the device’s IP address. Single-word names work only when your router provides local DNS."
        case .refused:
            return "The device is reachable, but nothing is accepting connections on port \(target.port). Check that the service is running and the port is right."
        case .timedOut:
            return "The device didn’t reply. It may be off or asleep, on a different network, or behind a firewall. Guest Wi-Fi networks often stop devices from reaching each other."
        case .unreachable:
            return "There’s no route to this address. Check that this iPhone and the device are on the same network and that the IP address is still current."
        case .secureConnectionFailed:
            return "The secure connection failed. The service may not offer HTTPS on this port; try http:// instead."
        case .noHTTPResponse:
            return target.secure
                ? "The port accepted the connection but didn’t answer like a web server. It may not serve web pages, or it may expect http:// instead."
                : "The port accepted the connection but didn’t answer like a web server. It may not serve web pages, or it may expect https:// instead."
        case .httpError(let code) where code >= 500:
            return "The server reported a problem (\(code)). Restarting the service or checking its logs may help."
        case .httpError(let code):
            return "The server answered with an error (\(code)). The page path may be wrong, or the service may need you to sign in."
        }
    }

    static let wrongInterface = "This iPhone isn’t on Wi-Fi. Local addresses usually work only on the same Wi-Fi network as the device."
    static let untrustedCertificate = "The certificate isn’t trusted, which is common for home devices with self-signed certificates. LAN Browser doesn’t bypass certificate errors, so try http:// if the device offers it."

    /// Parses `HTTP/1.1 200 OK` from the start of a response.
    static func statusCode(in response: String) -> Int? {
        let parts = response.prefix(while: { $0 != "\r" && $0 != "\n" }).split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]), (100...599).contains(code) else { return nil }
        return code
    }

    static func header(_ name: String, in response: String) -> String? {
        let head = response.components(separatedBy: "\r\n\r\n").first ?? response
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                return pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func report(url: URL, steps: [DiagnosticStep], date: Date = Date()) -> String {
        var lines = ["LAN Browser connection check", "Address: \(url.absoluteString)", "Checked: \(date.formatted(date: .abbreviated, time: .standard))", ""]
        for step in steps {
            let mark: String
            switch step.status {
            case .passed: mark = "✓"
            case .warning: mark = "!"
            case .failed: mark = "✗"
            case .skipped: mark = "–"
            case .pending, .running: mark = "…"
            }
            lines.append("\(mark) \(step.kind.title): \(step.detail)")
            if let advice = step.advice { lines.append("  \(advice)") }
        }
        return lines.joined(separator: "\n")
    }
}
