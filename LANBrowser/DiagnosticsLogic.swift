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
    let url: URL

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        self.url = url
        self.host = host
        secure = scheme == "https"
        port = url.port ?? (secure ? 443 : 80)
        // Keep the query, so a redirect to /login?next=/ is requested exactly as given.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var requestPath = components?.percentEncodedPath ?? ""
        if requestPath.isEmpty { requestPath = "/" }
        if let query = components?.percentEncodedQuery { requestPath += "?" + query }
        path = requestPath
    }

    var isLocal: Bool { ServiceCatalog.isLocalHost(host) }
    var hostHeader: String {
        let name = host.contains(":") ? "[\(host)]" : host
        return port == (secure ? 443 : 80) ? name : "\(name):\(port)"
    }
}

/// The device LAN Browser runs on, so advice names it correctly on iPhone, iPad and Mac.
enum HostDevice: String {
    case iPhone, iPad, mac = "Mac"
}

enum DiagnosticsText {
    static func advice(for failure: ConnectionFailure, target: DiagnosticTarget, device: HostDevice) -> String {
        switch failure {
        case .noNetwork:
            return "This \(device.rawValue) isn’t connected to a network. Turn on Wi-Fi and join the same network as your device."
        case .permissionDenied:
            if device == .mac {
                return "LAN Browser isn’t allowed to reach devices on your network. Turn on System Settings › Privacy & Security › Local Network › LAN Browser. If macOS just asked, click Allow, then Retry Checks."
            }
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
            return "There’s no route to this address. Check that this \(device.rawValue) and the device are on the same network and that the IP address is still current."
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

    static func wrongInterface(device: HostDevice) -> String {
        "This \(device.rawValue) isn’t on Wi-Fi. Local addresses usually work only on the same Wi-Fi network as the device."
    }
    static let untrustedCertificate = "The certificate isn’t trusted, which is common for home devices with self-signed certificates. LAN Browser still opens local addresses like this one and marks the page with a red “!”; tap it to compare the certificate’s fingerprint with the device."

    /// Parses `HTTP/1.1 200 OK` from the start of a response.
    static func statusCode(in response: String) -> Int? {
        let parts = response.prefix(while: { $0 != "\r" && $0 != "\n" }).split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]), (100...599).contains(code) else { return nil }
        return code
    }

    /// The page’s `<title>`, for naming web apps found by the port scan.
    static func htmlTitle(in response: String) -> String? {
        guard let open = response.range(of: "<title", options: .caseInsensitive),
              let start = response[open.upperBound...].firstIndex(of: ">"),
              let close = response.range(of: "</title>", options: .caseInsensitive, range: start..<response.endIndex) else { return nil }
        var title = String(response[response.index(after: start)..<close.lowerBound])
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "’"), ("&amp;", "&")] {
            title = title.replacingOccurrences(of: entity, with: character)
        }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : title
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

struct ResponseHeader: Equatable, Sendable {
    let name: String
    let value: String
}

/// The main page’s HTTP response as WebKit reported it, shown when it isn’t a plain 200.
struct PageResponse: Identifiable, Equatable, Sendable {
    let id = UUID()
    let method: String
    let url: String
    let statusCode: Int
    /// Sorted by name; iOS doesn’t preserve the order the server sent them in.
    let headers: [ResponseHeader]

    var statusLine: String { HTTPStatus.line(statusCode) }
    var isError: Bool { statusCode >= 400 }

    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The request and the headers that explain what came back, for the error screen.
    var summary: String {
        (["\(method) \(url)"] + ["Content-Type", "Content-Length", "Server", "Location"].compactMap { name in
            header(name).map { "\(name): \($0)" }
        }).joined(separator: "\n")
    }

    /// Plain-text copy of everything shown, for pasting into notes or a support request.
    var report: String {
        (["\(method) \(url)", "Status: \(statusLine)", ""] + headers.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
    }
}

enum HTTPStatus {
    /// Standard reason phrases (RFC 9110 and common extensions). WebKit doesn’t expose the
    /// server’s own phrase, and HTTP/2 doesn’t send one.
    static func phrase(_ code: Int) -> String? { phrases[code] }

    static func line(_ code: Int) -> String { phrase(code).map { "\(code) \($0)" } ?? "\(code)" }

    private static let phrases: [Int: String] = [
        100: "Continue", 101: "Switching Protocols", 103: "Early Hints",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content",
        205: "Reset Content", 206: "Partial Content", 207: "Multi-Status",
        300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified",
        307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout",
        409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large",
        414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed",
        418: "I’m a Teapot", 421: "Misdirected Request", 422: "Unprocessable Content", 423: "Locked",
        424: "Failed Dependency", 425: "Too Early", 426: "Upgrade Required", 428: "Precondition Required",
        429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable",
        504: "Gateway Timeout", 505: "HTTP Version Not Supported", 507: "Insufficient Storage", 508: "Loop Detected",
        511: "Network Authentication Required"
    ]
}

enum Redirects {
    static let limit = 5

    /// Where a redirect response points, resolved against the URL that sent it.
    /// Nil for non-redirects and 304 Not Modified, which isn’t a redirect.
    static func next(from url: URL, status: Int?, location: String?) -> URL? {
        guard let status, (300..<400).contains(status), status != 304, let location else { return nil }
        return URL(string: location, relativeTo: url)?.absoluteURL
    }
}

enum ErrorText {
    /// The exact error identifiers behind a failed load, so they can be searched or reported.
    static func details(domain: String, code: Int, url: String?, underlying: (domain: String, code: Int)?) -> String {
        var lines = ["Error: \(domain) \(code)"]
        if let underlying { lines.append("Underlying: \(underlying.domain) \(underlying.code)") }
        if let url { lines.append("URL: \(url)") }
        return lines.joined(separator: "\n")
    }
}

/// Ports browsers refuse to load (the Fetch standard’s “bad ports”), because they belong to
/// other protocols. WebKit drops these without reporting an error, which would leave a blank page.
enum BlockedPorts {
    static let ports: Set<Int> = [
        0, 1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77, 79, 87, 95, 101, 102, 103, 104,
        109, 110, 111, 113, 115, 117, 119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515,
        526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993, 995, 1719, 1720, 1723, 2049,
        3659, 4045, 4190, 5060, 5061, 6000, 6566, 6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080
    ]

    static func message(for url: URL) -> String? {
        guard let port = url.port, ports.contains(port) else { return nil }
        return "Browsers refuse to load port \(port), so no request was sent. Port \(port) belongs to another kind of service (it’s on the Fetch standard’s list of blocked ports), not a web page. Check the port number, or use the device’s own app for that service.\n\nURL: \(url.absoluteString)"
    }
}
