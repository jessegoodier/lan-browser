import Combine
import Foundation

/// What LAN Browser knows about one device. Keyed by host name when there is one, so a
/// custom name follows the device when its IP changes; IP-only devices are keyed by IP.
struct DeviceRecord: Codable, Equatable {
    var name: String?
    var address: String?
    var hostname: String?
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var records: [String: DeviceRecord] = [:]
    @Published var errorMessage: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "LANBrowser", directoryHint: .isDirectory)
            .appending(path: "devices.json")
        if let data = try? Data(contentsOf: self.fileURL) {
            // A damaged cache of names is not worth blocking the app for; start empty instead.
            records = (try? JSONDecoder().decode([String: DeviceRecord].self, from: data)) ?? [:]
        }
    }

    nonisolated static func key(_ host: String) -> String {
        var key = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if key.hasSuffix(".") { key.removeLast() }
        return key
    }

    nonisolated static func isIPAddress(_ host: String) -> Bool {
        let key = key(host)
        if key.contains(":") { return true }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// The host name without local-network suffixes, or the reverse-lookup name for an IP.
    nonisolated static func defaultName(for host: String, hostname: String? = nil) -> String {
        var name = isIPAddress(host) ? (hostname ?? host) : host
        if name.hasSuffix(".") { name.removeLast() }
        for suffix in [".local", ".localdomain", ".lan", ".home.arpa", ".home", ".internal"]
        where name.count > suffix.count && name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    func customName(for host: String) -> String? { records[Self.key(host)]?.name }

    func name(for host: String) -> String {
        let record = records[Self.key(host)]
        return record?.name ?? Self.defaultName(for: host, hostname: record?.hostname)
    }

    func address(for host: String) -> String? {
        Self.isIPAddress(host) ? nil : records[Self.key(host)]?.address
    }

    /// `name:port/path · IP`, omitting default ports, a bare `/` path, and an IP equal to the host.
    func label(for url: URL, address fallback: String? = nil) -> String {
        guard let host = url.host else { return url.absoluteString }
        var label = name(for: host)
        if let port = url.port, port != (url.scheme?.lowercased() == "https" ? 443 : 80) { label += ":\(port)" }
        if !url.path.isEmpty && url.path != "/" { label += url.path }
        if let address = address(for: host) ?? fallback, Self.key(address) != Self.key(host) { label += " · \(address)" }
        return label
    }

    @discardableResult
    func rename(_ host: String, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var record = records[Self.key(host)] ?? DeviceRecord()
        record.name = trimmed.isEmpty || trimmed == Self.defaultName(for: host, hostname: record.hostname) ? nil : trimmed
        guard persist(updating: host, with: record) else {
            errorMessage = "The device name couldn’t be saved. Please try again."
            return false
        }
        return true
    }

    /// Forgets every custom name, last-seen IP and reverse-lookup name.
    func resetAll() {
        try? FileManager.default.removeItem(at: fileURL)
        records = [:]
    }

    /// Remembers the latest IP for a host name, or the reverse-lookup name for an IP.
    func record(address: String? = nil, hostname: String? = nil, for host: String) {
        var record = records[Self.key(host)] ?? DeviceRecord()
        if let address, !Self.isIPAddress(host) { record.address = address }
        if let hostname { record.hostname = hostname }
        persist(updating: host, with: record)
    }

    @discardableResult
    private func persist(updating host: String, with record: DeviceRecord) -> Bool {
        let key = Self.key(host)
        guard records[key] != record else { return true }
        var updated = records
        updated[key] = record == DeviceRecord() ? nil : record
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updated).write(to: fileURL, options: .atomic)
            records = updated
            return true
        } catch {
            return false
        }
    }
}
