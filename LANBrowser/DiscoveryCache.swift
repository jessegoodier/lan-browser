import Foundation

/// The most recent Bonjour scan, kept until the user scans again or clears it.
struct DiscoveryScan: Codable, Equatable {
    var date: Date
    /// Fingerprint of the network the scan ran on, used to say when results may be stale.
    var network: String?
    var services: [DiscoveredService]
}

struct DiscoveryCache {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "LANBrowser", directoryHint: .isDirectory)
            .appending(path: "discovered.json")
    }

    func load() -> DiscoveryScan? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiscoveryScan.self, from: data)
    }

    func save(_ scan: DiscoveryScan) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(scan).write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
