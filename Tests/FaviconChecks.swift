import Foundation
import ImageIO

@main
struct FaviconChecks {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LANBrowserFaviconChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeFile = directory.appending(path: "bookmarks.json")
        let store = BookmarkStore(fileURL: storeFile)
        let services = [DiscoveredService.Source.bonjour, .portScan].enumerated().map { index, source in
            DiscoveredService(name: "Service \(index)", type: "_http._tcp", url: URL(string: "http://fixture.local:\(8889 + index)/")!, foundBy: source)
        }
        for service in services {
            precondition(store.save(Bookmark(title: service.name, url: service.url.absoluteString)))
        }
        let defaultsName = "LANBrowserFaviconChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let cache = DiscoveryCache(fileURL: directory.appending(path: "discovered.json"))
        cache.save(DiscoveryScan(date: Date(), services: services))
        let devices = DeviceStore(fileURL: directory.appending(path: "devices.json"))
        let network = LocalNetwork(devices: devices, defaults: defaults, cache: cache)
        let original = try Data(contentsOf: storeFile)
        await network.refresh() // Disabled discovery must not initiate a scan or touch bookmarks.
        network.stopScanning()
        network.clearResults()
        let afterClear = try Data(contentsOf: storeFile)
        precondition(afterClear == original)
        precondition(BookmarkStore(fileURL: storeFile).bookmarks == store.bookmarks)

        guard CommandLine.arguments.count > 1, let base = URL(string: CommandLine.arguments[1]) else {
            print("Passed bookmark/discovery isolation checks. Pass a running fixture URL to test favicon requests.")
            return
        }
        cache.save(DiscoveryScan(date: Date(), services: services))
        defaults.set(true, forKey: "localNetworkFeatures")
        defaults.set(true, forKey: "localNetworkAutoScanned")
        let enabledNetwork = LocalNetwork(devices: devices, defaults: defaults, cache: cache)
        await enabledNetwork.refresh()
        enabledNetwork.stopScanning()
        enabledNetwork.clearResults()
        enabledNetwork.isEnabled = false
        let afterScan = try Data(contentsOf: storeFile)
        precondition(afterScan == original, "Refreshing, cancelling and clearing enabled discovery must preserve all bookmarks")

        func page(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
        for path in ["/icons/relative", "/icons/redirect", "/icons/chunked"] {
            let png = await FaviconLoader.shared.load(page(path))
            precondition(png != nil, "Missing valid icon: \(path)")
            let source = CGImageSourceCreateWithData(png! as CFData, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            precondition(image.width <= 64 && image.height <= 64)
        }
        for path in ["/icons/missing", "/icons/malformed", "/icons/oversized", "/icons/external", "/icons/fallback"] {
            let png = await FaviconLoader.shared.load(page(path))
            precondition(png == nil, "Unexpected icon for failing fixture: \(path)")
        }
        let cancelled = Task { await FaviconLoader.shared.load(page("/icons/delayed?cancelled")) }
        try await Task.sleep(for: .milliseconds(200))
        let cancelledAt = ContinuousClock.now
        cancelled.cancel()
        let cancelledValue = await cancelled.value
        precondition(cancelledValue == nil && ContinuousClock.now - cancelledAt < .seconds(1), "Cancellation must close the request promptly")

        let first = Task { await FaviconLoader.shared.load(page("/icons/delayed?shared")) }
        let second = Task { await FaviconLoader.shared.load(page("/icons/delayed?shared")) }
        try await Task.sleep(for: .milliseconds(200))
        first.cancel()
        let firstValue = await first.value
        let secondValue = await second.value
        precondition(firstValue == nil && secondValue != nil, "Cancelling one waiter must preserve the other’s request")

        let bookmark = Bookmark(title: "Slow", url: page("/icons/delayed?deleted").absoluteString)
        precondition(store.save(bookmark))
        let pending = Task {
            if let png = await FaviconLoader.shared.load(page("/icons/delayed?deleted")) {
                store.updateFavicon(png, id: bookmark.id, url: bookmark.url)
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        store.delete(at: IndexSet(integer: store.bookmarks.count - 1))
        await pending.value
        precondition(store.existing(for: bookmark.url) == nil, "Late response must not resurrect a bookmark")

        if CommandLine.arguments.count > 2, let fallback = URL(string: CommandLine.arguments[2]) {
            let png = await FaviconLoader.shared.load(fallback.appending(path: "icons/fallback"))
            precondition(png != nil, "Root favicon fallback should load")
        }
        print("Passed favicon fixture checks (links, fallback, redirects, chunking, limits, cancellation, shared requests, and deleted bookmarks).")
    }
}
