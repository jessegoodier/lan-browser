import Combine
import Foundation

/// Runs the “Why can’t I connect?” checks in order, publishing each step as it finishes.
@MainActor
final class ConnectionDiagnostics: ObservableObject {
    let url: URL
    @Published private(set) var steps = DiagnosticKind.allCases.map { DiagnosticStep(kind: $0) }
    @Published private(set) var isRunning = false

    init(url: URL) { self.url = url }

    var report: String { DiagnosticsText.report(url: url, steps: steps) }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        steps = DiagnosticKind.allCases.map { DiagnosticStep(kind: $0) }
        guard let target = DiagnosticTarget(url: url) else {
            update(.network, .failed, "LAN Browser can check only http:// and https:// addresses.")
            skipRemaining(after: .network)
            return
        }

        update(.network, .running, "Checking…")
        let network = await NetworkProbe.currentNetwork()
        guard network.connected else {
            update(.network, .failed, "Not connected", advice: DiagnosticsText.advice(for: .noNetwork, target: target))
            skipRemaining(after: .network)
            return
        }
        let networkDetail = [network.interface, network.address].compactMap { $0 }.joined(separator: " · ")
        if target.isLocal && !network.onWiFi {
            update(.network, .warning, networkDetail, advice: DiagnosticsText.wrongInterface)
        } else {
            update(.network, .passed, networkDetail)
        }

        // Probing a local address is what reveals (or first requests) Local Network access,
        // so the port check runs here and its result is reused below.
        var portOutcome: NetworkProbe.Outcome?
        if target.isLocal {
            update(.permission, .running, "Checking…")
            let outcome = await NetworkProbe.connect(host: target.host, port: target.port)
            if outcome == .failed(.permissionDenied) {
                update(.permission, .failed, "Not allowed", advice: DiagnosticsText.advice(for: .permissionDenied, target: target))
                skipRemaining(after: .permission)
                return
            }
            update(.permission, .passed, "Allowed")
            portOutcome = outcome
        } else {
            update(.permission, .skipped, "Not needed for internet addresses")
        }

        update(.dns, .running, "Looking up \(target.host)…")
        switch await NetworkProbe.resolve(target.host) {
        case .success(let addresses) where addresses == [target.host]:
            update(.dns, .passed, "IP address, no lookup needed")
        case .success(let addresses):
            update(.dns, .passed, "\(target.host) → \(addresses.prefix(3).joined(separator: ", "))")
        case .failure(let failure):
            update(.dns, .failed, "\(target.host) not found", advice: DiagnosticsText.advice(for: failure, target: target))
            skipRemaining(after: .dns)
            return
        }

        update(.port, .running, "Connecting to port \(target.port)…")
        let outcome: NetworkProbe.Outcome
        if let portOutcome { outcome = portOutcome } else { outcome = await NetworkProbe.connect(host: target.host, port: target.port) }
        switch outcome {
        case .connected:
            update(.port, .passed, "Port \(target.port) is open")
        case .failed(let failure):
            update(.port, .failed, portDetail(failure, port: target.port), advice: DiagnosticsText.advice(for: failure, target: target))
            skipRemaining(after: .port)
            return
        }

        update(.http, .running, target.secure ? "Requesting over HTTPS…" : "Requesting over HTTP…")
        let http = await NetworkProbe.http(target)
        var parts: [String] = []
        if let code = http.statusCode { parts.append("HTTP \(code)") }
        if let server = http.server { parts.append(server) }
        if let trusted = http.certificateTrusted { parts.append(trusted ? "Certificate trusted" : "Certificate not trusted") }
        let detail = parts.isEmpty ? "No web response" : parts.joined(separator: " · ")
        if let failure = http.failure {
            update(.http, .failed, detail, advice: DiagnosticsText.advice(for: failure, target: target))
        } else if http.certificateTrusted == false {
            update(.http, .warning, detail, advice: DiagnosticsText.untrustedCertificate)
        } else {
            update(.http, .passed, detail)
        }
    }

    private func portDetail(_ failure: ConnectionFailure, port: Int) -> String {
        switch failure {
        case .refused: return "Connection refused on port \(port)"
        case .timedOut: return "No reply on port \(port)"
        case .nameNotFound: return "Name not found"
        default: return "Couldn’t reach port \(port)"
        }
    }

    private func update(_ kind: DiagnosticKind, _ status: DiagnosticStatus, _ detail: String, advice: String? = nil) {
        steps[kind.rawValue] = DiagnosticStep(kind: kind, status: status, detail: detail, advice: advice)
    }

    private func skipRemaining(after kind: DiagnosticKind) {
        for later in DiagnosticKind.allCases where later.rawValue > kind.rawValue {
            update(later, .skipped, "Skipped")
        }
    }
}
