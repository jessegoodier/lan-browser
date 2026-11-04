import Foundation
import ImageIO
import Network
import Security
import UniformTypeIdentifiers

@MainActor
final class FaviconLoader {
    static let shared = FaviconLoader()
    private struct Job {
        var task: Task<Data?, Never>
        var waiters: Set<UUID>
    }
    private var jobs: [String: Job] = [:]
    private var active = 0

    func load(_ url: URL) async -> Data? {
        guard !Task.isCancelled, let key = BrowserAddress.bookmarkKey(url.absoluteString) else { return nil }
        let waiter = UUID()
        if jobs[key] != nil {
            jobs[key]?.waiters.insert(waiter)
        } else {
            let task = Task { [self] () -> Data? in
                while active >= 4 {
                    do { try await Task.sleep(for: .milliseconds(25)) } catch { return nil }
                }
                guard !Task.isCancelled else { return nil }
                active += 1
                defer { active -= 1 }
                return await Self.fetch(url)
            }
            jobs[key] = Job(task: task, waiters: [waiter])
        }
        let task = jobs[key]!.task
        let data = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.release(key, waiter: waiter) }
        }
        release(key, waiter: waiter)
        return Task.isCancelled ? nil : data
    }

    private func release(_ key: String, waiter: UUID) {
        guard jobs[key]?.waiters.remove(waiter) != nil else { return }
        if jobs[key]?.waiters.isEmpty == true {
            jobs.removeValue(forKey: key)?.task.cancel()
        }
    }

    private nonisolated static func fetch(_ page: URL) async -> Data? {
        let html = await follow(page, origin: page, limit: FaviconPolicy.htmlLimit)
        let finalPage = html?.url ?? page
        let text = html.flatMap { String(data: $0.response.body, encoding: .utf8) ?? String(data: $0.response.body, encoding: .isoLatin1) } ?? ""
        for candidate in FaviconPolicy.candidates(in: text, page: finalPage) {
            guard !Task.isCancelled else { return nil }
            guard let reply = await follow(candidate, origin: page, limit: FaviconPolicy.imageLimit),
                  let png = thumbnail(reply.response.body) else { continue }
            return png
        }
        return nil
    }

    private nonisolated static func follow(_ start: URL, origin: URL, limit: Int) async -> (url: URL, response: FaviconResponse)? {
        var url = start
        var visited: Set<URL> = []
        for _ in 0...5 {
            guard !Task.isCancelled, FaviconPolicy.sameOrigin(url, origin), visited.insert(url).inserted,
                  let response = await request(url, limit: limit) else { return nil }
            if [301, 302, 303, 307, 308].contains(response.status) {
                guard let location = response.headers["location"], let next = FaviconPolicy.resolve(location, relativeTo: url) else { return nil }
                url = next
            } else {
                return response.status == 200 ? (url, response) : nil
            }
        }
        return nil
    }

    private nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private nonisolated static func request(_ url: URL, limit: Int) async -> FaviconResponse? {
        guard let target = DiagnosticTarget(url: url), let port = NWEndpoint.Port(rawValue: UInt16(target.port)),
              !BlockedPorts.ports.contains(target.port) else { return nil }
        let parameters: NWParameters
        if target.secure {
            // Network.framework performs normal certificate and hostname validation.
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, target.host)
            parameters = NWParameters(tls: tls)
        } else {
            parameters = .tcp
        }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: parameters)
        let reader = FaviconReader(connection: connection, limit: limit)
        return await withTaskCancellationHandler {
            await reader.run(target: target)
        } onCancel: {
            reader.cancel()
        }
    }
}

/// Every callback, timeout and cancellation converges on one completion on this serial queue.
private final class FaviconReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LANBrowser.Favicon")
    private let connection: NWConnection
    private let limit: Int
    private var continuation: CheckedContinuation<FaviconResponse?, Never>?
    private var finished = false
    private var bytes = Data()
    private var timeout: DispatchWorkItem?

    init(connection: NWConnection, limit: Int) {
        self.connection = connection
        self.limit = limit
    }

    func cancel() { queue.async { self.finish(nil) } }

    func run(target: DiagnosticTarget) async -> FaviconResponse? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.finished else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                self.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let request = "GET \(target.path) HTTP/1.1\r\nHost: \(target.hostHeader)\r\nUser-Agent: LANBrowser-Favicon\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"
                        self.connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                            if error != nil { self.finish(nil) } else { self.receive() }
                        })
                    case .failed, .waiting, .cancelled: self.finish(nil)
                    default: break
                    }
                }
                let timeout = DispatchWorkItem { self.finish(nil) }
                self.timeout = timeout
                self.queue.asyncAfter(deadline: .now() + 5, execute: timeout)
                self.connection.start(queue: self.queue)
            }
        }
    }

    private func receive() {
        guard !finished else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
            guard !self.finished else { return }
            if let data { self.bytes.append(data) }
            switch FaviconHTTP.parse(self.bytes, limit: self.limit, eof: complete || error != nil) {
            case .complete(let response): self.finish(response)
            case .rejected: self.finish(nil)
            case .incomplete: self.receive()
            }
        }
    }

    private func finish(_ response: FaviconResponse?) {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        timeout = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(returning: response)
        continuation = nil
    }
}
