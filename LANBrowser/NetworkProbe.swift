import Foundation
import Network
import Security

/// One-shot native checks shared by the status dots and connection diagnostics.
/// Raw NWConnection is used instead of URLSession so plain-HTTP public hosts aren’t blocked by ATS.
enum NetworkProbe {
    enum Outcome: Equatable, Sendable {
        case connected
        case failed(ConnectionFailure)
    }

    struct HTTPResult: Sendable {
        var failure: ConnectionFailure?
        var statusCode: Int?
        var server: String?
        var certificateTrusted: Bool?
        var title: String?
        var location: String?
    }

    struct NetworkSnapshot: Sendable {
        var connected: Bool
        var interface: String
        var onWiFi: Bool
        var address: String?
    }

    private static let queue = DispatchQueue(label: "LANBrowser.NetworkProbe", attributes: .concurrent)

    static func connect(host: String, port: Int, timeout: TimeInterval = 3) async -> Outcome {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return .failed(.unreachable) }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let once = Once<Outcome>()
        let outcome = await withCheckedContinuation { continuation in
            once.set(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.connected)
                case .waiting(let error), .failed(let error):
                    once.resume(.failed(classify(error, path: connection.currentPath)))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(.failed(.timedOut)) }
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        return outcome
    }

    /// Sends a GET (some embedded servers reject HEAD) and reads only the first chunk of the reply.
    /// For HTTPS, certificate trust is recorded but not enforced, so an untrusted certificate is
    /// reported instead of hiding the server.
    static func http(_ target: DiagnosticTarget, timeout: TimeInterval = 5) async -> HTTPResult {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: target.port)) else { return HTTPResult(failure: .unreachable) }
        let trust = Box<Bool?>(nil)
        let parameters: NWParameters
        if target.secure {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, secTrust, complete in
                trust.value = SecTrustEvaluateWithError(sec_trust_copy_ref(secTrust).takeRetainedValue(), nil)
                complete(true)
            }, queue)
            parameters = NWParameters(tls: tls)
        } else {
            parameters = .tcp
        }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: endpointPort, using: parameters)
        let request = "GET \(target.path) HTTP/1.1\r\nHost: \(target.hostHeader)\r\nUser-Agent: LANBrowser-Diagnostics\r\nAccept: */*\r\nConnection: close\r\n\r\n"
        let once = Once<HTTPResult>()
        var result = await withCheckedContinuation { continuation in
            once.set(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                        let text = data.flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) } ?? ""
                        guard let code = DiagnosticsText.statusCode(in: text) else { once.resume(HTTPResult(failure: .noHTTPResponse)); return }
                        once.resume(HTTPResult(statusCode: code, server: DiagnosticsText.header("Server", in: text), title: DiagnosticsText.htmlTitle(in: text),
                                               location: DiagnosticsText.header("Location", in: text)))
                    }
                case .waiting(let error), .failed(let error):
                    if case .tls = error { once.resume(HTTPResult(failure: .secureConnectionFailed)); return }
                    once.resume(HTTPResult(failure: classify(error, path: connection.currentPath)))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(HTTPResult(failure: .noHTTPResponse)) }
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        result.certificateTrusted = target.secure ? trust.value : nil
        if result.failure == nil, let code = result.statusCode, code >= 400 { result.failure = .httpError(code) }
        return result
    }

    /// Resolves a host name with the system resolver, the same one WebKit uses.
    static func resolve(_ host: String) async -> Result<[String], ConnectionFailure> {
        if IPv4Address(host) != nil || IPv6Address(host) != nil { return .success([host]) }
        return await Task.detached {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var list: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &list)
            defer { if list != nil { freeaddrinfo(list) } }
            guard status == 0 else { return .failure(.nameNotFound) }
            var addresses: [String] = []
            var cursor = list
            while let info = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: buffer)
                    if !addresses.contains(address) { addresses.append(address) }
                }
                cursor = info.pointee.ai_next
            }
            return addresses.isEmpty ? .failure(.nameNotFound) : .success(addresses)
        }.value
    }

    struct Sighting: Sendable {
        var address: String?
        var hostname: String?
    }

    /// The current IP for a host name, or the reverse-lookup name for an IP (looked up once per IP).
    static func sighting(of host: String, reverseLookup: Bool) async -> Sighting {
        if DeviceStore.isIPAddress(host) {
            return Sighting(hostname: reverseLookup ? await hostname(for: host) : nil)
        }
        return Sighting(address: await displayAddress(for: host))
    }

    /// Requests a page and follows its redirects like a browser, up to `Redirects.limit`,
    /// returning every hop so the whole chain can be shown.
    static func follow(_ target: DiagnosticTarget, timeout: TimeInterval = 5) async -> [(url: URL, result: HTTPResult)] {
        var hops: [(url: URL, result: HTTPResult)] = []
        var next: URL? = target.url
        while let url = next, hops.count <= Redirects.limit, let hopTarget = DiagnosticTarget(url: url) {
            let result = await http(hopTarget, timeout: timeout)
            hops.append((url, result))
            next = Redirects.next(from: url, status: result.statusCode, location: result.location)
            if let next, hops.contains(where: { $0.url == next }) { break }
        }
        return hops
    }

    /// Whether an open port serves a web page, trying the scheme it most likely speaks first.
    /// Any HTTP status counts, since a login page or 404 still means a web app is there.
    static func webEndpoint(host: String, port: Int) async -> WebFinding? {
        for scheme in PortScan.prefersHTTPS(port: port) ? ["https", "http"] : ["http", "https"] {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            if port != (scheme == "https" ? 443 : 80) { components.port = port }
            components.path = "/"
            guard let url = components.url, let target = DiagnosticTarget(url: url) else { continue }
            let hops = await follow(target, timeout: 3)
            if let first = hops.first?.result, let status = first.statusCode {
                // Name the row from the page the redirects end on, not the placeholder page.
                let final = hops.last?.result
                let title = hops.count > 1 ? final?.title : first.title
                return WebFinding(host: host, port: port, url: url, status: status, title: title,
                                  server: first.server ?? final?.server, location: first.location)
            }
        }
        return nil
    }

    /// The address to show beside a host name, preferring IPv4 over long IPv6 forms.
    static func displayAddress(for host: String) async -> String? {
        guard case .success(let addresses) = await resolve(host) else { return nil }
        return addresses.first { !$0.contains(":") } ?? addresses.first
    }

    /// Reverse lookup through the system resolver, which also answers from Bonjour on the LAN.
    static func hostname(for address: String) async -> String? {
        await Task.detached { () -> String? in
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST
            var list: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(address, nil, &hints, &list) == 0, let info = list else { return nil }
            defer { freeaddrinfo(list) }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD) == 0 else { return nil }
            let name = String(cString: buffer)
            return name.isEmpty || name == address ? nil : name
        }.value
    }

    /// Bonjour’s SRV record names the device (e.g. `omarchy.local`), which NWBrowser doesn’t expose.
    static func resolveService(name: String, type: String, domain: String, interfaceIndex: UInt32, timeout: TimeInterval = 5) async -> (host: String, port: Int)? {
        let once = Once<(String, Int)?>()
        let context = Unmanaged.passRetained(once)
        var reference: DNSServiceRef?
        let error = DNSServiceResolve(&reference, 0, interfaceIndex, name, type, domain, { _, _, _, error, _, target, port, _, _, context in
            guard let context else { return }
            let once = Unmanaged<Once<(String, Int)?>>.fromOpaque(context).takeUnretainedValue()
            guard error == kDNSServiceErr_NoError, let target else { once.resume(nil); return }
            var host = String(cString: target)
            if host.hasSuffix(".") { host.removeLast() }
            once.resume((host, Int(UInt16(bigEndian: port))))
        }, context.toOpaque())
        guard error == kDNSServiceErr_NoError, let reference else {
            context.release()
            return nil
        }
        nonisolated(unsafe) let service = reference
        DNSServiceSetDispatchQueue(service, resolveQueue)
        resolveQueue.asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
        let result = await withCheckedContinuation { once.set($0) }
        // The callback runs on resolveQueue, so deallocating there guarantees it won’t fire again.
        resolveQueue.async {
            DNSServiceRefDeallocate(service)
            context.release()
        }
        return result.map { (host: $0.0, port: $0.1) }
    }

    private static let resolveQueue = DispatchQueue(label: "LANBrowser.NetworkProbe.resolve")

    static func currentNetwork() async -> NetworkSnapshot {
        let monitor = NWPathMonitor()
        let once = Once<NWPath>()
        let path = await withCheckedContinuation { continuation in
            once.set(continuation)
            monitor.pathUpdateHandler = { once.resume($0) }
            monitor.start(queue: queue)
        }
        monitor.cancel()
        let interface: String
        if path.usesInterfaceType(.wifi) { interface = "Wi-Fi" }
        else if path.usesInterfaceType(.wiredEthernet) { interface = "Ethernet" }
        else if path.usesInterfaceType(.cellular) { interface = "Cellular" }
        else if path.status == .satisfied { interface = "Other" }
        else { interface = "None" }
        let name = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }?.name
        return NetworkSnapshot(
            connected: path.status == .satisfied,
            interface: interface,
            onWiFi: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet),
            address: name.flatMap(ipv4Address)
        )
    }

    nonisolated static func ipv4Address(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var cursor = list
        while let entry = cursor {
            if String(cString: entry.pointee.ifa_name) == interface, let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: buffer)
                }
            }
            cursor = entry.pointee.ifa_next
        }
        return nil
    }

    /// The IPv4 network an interface is on, e.g. `10.0.0.0/22`. Unlike the device’s own
    /// address, this stays the same when DHCP hands out a different IP.
    nonisolated static func ipv4Network(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var cursor = list
        while let entry = cursor {
            if String(cString: entry.pointee.ifa_name) == interface,
               let address = entry.pointee.ifa_addr, let netmask = entry.pointee.ifa_netmask,
               address.pointee.sa_family == UInt8(AF_INET) {
                let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                let network = ip & mask
                let octets = [24, 16, 8, 0].map { String((network >> UInt32($0)) & 0xFF) }
                return "\(octets.joined(separator: "."))/\(mask.nonzeroBitCount)"
            }
            cursor = entry.pointee.ifa_next
        }
        return nil
    }

    static func classify(_ error: NWError, path: NWPath?) -> ConnectionFailure {
        if path?.unsatisfiedReason == .localNetworkDenied { return .permissionDenied }
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return .refused
            case .ETIMEDOUT: return .timedOut
            case .ENETDOWN: return path?.status == .satisfied ? .unreachable : .noNetwork
            default: return .unreachable
            }
        case .dns(let code):
            return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) ? .permissionDenied : .nameNotFound
        case .tls:
            return .secureConnectionFailed
        default:
            return .unreachable
        }
    }
}

/// Resumes a continuation exactly once, whichever callback or timeout fires first.
final class Once<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var early: Value?

    func set(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if let early { lock.unlock(); continuation.resume(returning: early); return }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ value: Value) {
        lock.lock()
        guard let continuation else {
            if early == nil { early = value }
            lock.unlock()
            return
        }
        self.continuation = nil
        early = value
        lock.unlock()
        continuation.resume(returning: value)
    }
}

final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
