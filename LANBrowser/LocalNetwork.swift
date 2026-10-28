import Combine
import Foundation
import Network

enum Reachability: Equatable, Sendable {
    case checking, reachable, unreachable
}

/// Opt-in Bonjour discovery and bookmark reachability. Nothing here runs until the user
/// turns on Local Network Features, because these native checks trigger the iOS
/// Local Network prompt (WebKit page loads do not). Discovery runs once when the feature is
/// first turned on and afterwards only when the user asks; the last scan is kept on disk.
@MainActor
final class LocalNetwork: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { cardDismissed = true }
            enabledChanged()
        }
    }
    @Published var cardDismissed: Bool {
        didSet { defaults.set(cardDismissed, forKey: Self.cardKey) }
    }
    @Published private(set) var services: [DiscoveredService] = []
    @Published private(set) var status: [Bookmark.ID: Reachability] = [:]
    @Published private(set) var serviceStatus: [DiscoveredService.ID: Reachability] = [:]
    @Published private(set) var accessDenied = false
    /// True while a scan runs; rows keep their arrival order until it settles.
    @Published private(set) var isSearching = false
    @Published private(set) var lastScan: Date?
    /// The device has moved to a different network since the last scan.
    @Published private(set) var networkChanged = false

    private static let enabledKey = "localNetworkFeatures"
    private static let cardKey = "localNetworkCardDismissed"
    private static let autoScanKey = "localNetworkAutoScanned"
    private static let maxConcurrentChecks = 4
    private static let settleDelay = Duration.seconds(2)
    private static let maxSearch = Duration.seconds(10)
    let devices: DeviceStore
    private let defaults: UserDefaults
    private let cache: DiscoveryCache
    private var browsers: [NWBrowser] = []
    private var resolved: [String: DiscoveredService] = [:]
    private var resolving: Set<String> = []
    private var order: [String] = []
    private var settleTask: Task<Void, Never>?
    private var searchStarted = ContinuousClock.now
    private var pathMonitor: NWPathMonitor?
    private var currentNetwork: String?
    private var scannedNetwork: String?
    private var visible = false
    private var bookmarks: [Bookmark] = []
    private var checkedURLs: [Bookmark.ID: String] = [:]
    private var checkTokens: [Bookmark.ID: UUID] = [:]
    private var reverseLookups: Set<String> = []
    /// The one automatic scan is still owed, e.g. after updating from a version without a cache.
    private var autoScanPending = false

    init(devices: DeviceStore, defaults: UserDefaults = .standard, cache: DiscoveryCache = DiscoveryCache()) {
        self.devices = devices
        self.defaults = defaults
        self.cache = cache
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        cardDismissed = defaults.bool(forKey: Self.cardKey)
        if isEnabled {
            loadCache()
            startMonitoring()
            autoScanPending = lastScan == nil && !defaults.bool(forKey: Self.autoScanKey)
        }
    }

    /// Status checks run only while the bookmark list is on screen and the app is in the foreground.
    func setVisible(_ visible: Bool, bookmarks: [Bookmark]) {
        self.bookmarks = bookmarks
        guard self.visible != visible else { return }
        self.visible = visible
        if visible && isEnabled {
            if autoScanPending { autoScan() }
            Task { await checkAll() }
        } else {
            checkTokens.removeAll()
        }
    }

    /// A scan interrupted by the app leaving the foreground is dropped; the previous one is kept.
    func setForeground(_ foreground: Bool) {
        if !foreground && isSearching { cancelScan() }
    }

    /// Checks bookmarks that are new or whose address changed since their last check.
    func bookmarksChanged(_ bookmarks: [Bookmark]) {
        self.bookmarks = bookmarks
        let ids = Set(bookmarks.map(\.id))
        status = status.filter { ids.contains($0.key) }
        checkedURLs = checkedURLs.filter { ids.contains($0.key) }
        guard isEnabled && visible else { return }
        Task { await check(bookmarks.filter { checkedURLs[$0.id] != $0.url }) }
    }

    /// Pull to refresh: scan again and re-check every bookmark.
    func refresh() async {
        guard isEnabled else { return }
        scan()
        await check(bookmarks)
    }

    func scan() {
        guard isEnabled else { return }
        startBrowsing()
    }

    private func autoScan() {
        autoScanPending = false
        defaults.set(true, forKey: Self.autoScanKey)
        scan()
    }

    func clearResults() {
        if isSearching { stopBrowsers() }
        isSearching = false
        cache.clear()
        services = []
        serviceStatus = [:]
        lastScan = nil
        scannedNetwork = nil
        networkChanged = false
    }

    func remove(_ service: DiscoveredService) {
        services.removeAll { $0.id == service.id }
        serviceStatus[service.id] = nil
        guard !isSearching, let lastScan else { return }
        cache.save(DiscoveryScan(date: lastScan, network: scannedNetwork, services: services))
    }

    private func enabledChanged() {
        if isEnabled {
            startMonitoring()
            loadCache()
            if lastScan == nil { autoScan() }
            if visible { Task { await checkAll() } }
        } else {
            if isSearching { cancelScan() }
            pathMonitor?.cancel()
            pathMonitor = nil
            currentNetwork = nil
            checkTokens.removeAll()
            status.removeAll()
            serviceStatus.removeAll()
            checkedURLs.removeAll()
        }
    }

    private func loadCache() {
        let scan = cache.load()
        services = scan?.services ?? []
        lastScan = scan?.date
        scannedNetwork = scan?.network
        updateNetworkChanged()
    }

    private func startMonitoring() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // Router address plus the IPv4 network; either alone can be missing or shared by unrelated networks.
            let lan = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }
            let parts = path.gateways.map { "\($0)" }.sorted() + [lan.flatMap { NetworkProbe.ipv4Network(of: $0.name) }].compactMap { $0 }
            let fingerprint = parts.isEmpty ? nil : parts.joined(separator: "|")
            Task { @MainActor [weak self] in self?.pathChanged(fingerprint) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func pathChanged(_ fingerprint: String?) {
        let previous = currentNetwork
        currentNetwork = fingerprint
        updateNetworkChanged()
        guard previous != nil, previous != fingerprint, isEnabled, visible else { return }
        Task { await checkAll() }
    }

    private func updateNetworkChanged() {
        guard let currentNetwork, let scannedNetwork, !isSearching else { networkChanged = false; return }
        networkChanged = currentNetwork != scannedNetwork
    }

    // MARK: Discovery

    private func startBrowsing() {
        stopBrowsers()
        resolved.removeAll()
        resolving.removeAll()
        order = []
        services = []
        serviceStatus = [:]
        accessDenied = false
        for type in ServiceCatalog.types {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                guard case .waiting(let error) = state, case .dns(let code) = error,
                      code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) else { return }
                Task { @MainActor [weak self] in self?.accessDenied = true }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap(Found.init)
                Task { @MainActor [weak self] in self?.update(type: type, found: found) }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
        isSearching = true
        networkChanged = false
        searchStarted = .now
        scheduleSettle()
    }

    private func stopBrowsers() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        settleTask?.cancel()
        settleTask = nil
    }

    private func cancelScan() {
        stopBrowsers()
        isSearching = false
        resolved.removeAll()
        resolving.removeAll()
        loadCache()
    }

    private struct Found: Sendable {
        let key: String
        let name: String
        let type: String
        let domain: String
        let interfaceIndex: UInt32
        let endpoint: NWEndpoint
        let txt: [String: String]

        init?(_ result: NWBrowser.Result) {
            guard case .service(let name, let type, let domain, let interface) = result.endpoint else { return nil }
            let normalized = type.hasSuffix(".") ? String(type.dropLast()) : type
            key = "\(normalized)|\(name)"
            self.name = name
            self.type = normalized
            self.domain = domain
            interfaceIndex = interface.map { UInt32($0.index) } ?? 0
            endpoint = result.endpoint
            if case .bonjour(let record) = result.metadata { txt = record.dictionary } else { txt = [:] }
        }
    }

    private func update(type: String, found: [Found]) {
        guard isSearching else { return }
        let keys = Set(found.map(\.key))
        resolved = resolved.filter { !$0.key.hasPrefix(type + "|") || keys.contains($0.key) }
        publishServices()
        scheduleSettle()
        for service in found where resolved[service.key] == nil && !resolving.contains(service.key) {
            resolving.insert(service.key)
            Task {
                let discovered = await Self.discover(service)
                resolving.remove(service.key)
                guard isSearching, let discovered else { return }
                if let address = discovered.address, let host = discovered.url.host { devices.record(address: address, for: host) }
                resolved[service.key] = discovered
                publishServices()
                scheduleSettle()
            }
        }
    }

    /// Keeps rows where they are and adds new ones at the end, so a row doesn’t move under
    /// a finger while results are still arriving. Sorting happens once, when the scan settles.
    private func publishServices() {
        let merged = ServiceCatalog.merged(Array(resolved.values))
        let byKey = Dictionary(uniqueKeysWithValues: merged.map { (ServiceCatalog.deviceKey($0.url), $0) })
        order.removeAll { byKey[$0] == nil }
        order += merged.map { ServiceCatalog.deviceKey($0.url) }.filter { !order.contains($0) }
        services = order.compactMap { byKey[$0] }
    }

    /// Ends the scan once results stop arriving, then saves it as the new last scan.
    private func scheduleSettle() {
        guard isSearching else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            if !resolving.isEmpty && ContinuousClock.now - searchStarted < Self.maxSearch {
                scheduleSettle()
                return
            }
            stopBrowsers()
            isSearching = false
            services = ServiceCatalog.merged(Array(resolved.values))
            let now = Date()
            lastScan = now
            scannedNetwork = currentNetwork
            networkChanged = false
            cache.save(DiscoveryScan(date: now, network: currentNetwork, services: services))
            await checkServices()
        }
    }

    /// Prefers the device’s Bonjour host name so a saved bookmark survives IP changes,
    /// falling back to the IP when the service can’t be resolved by name.
    private nonisolated static func discover(_ service: Found) async -> DiscoveredService? {
        if let target = await NetworkProbe.resolveService(name: service.name, type: service.type, domain: service.domain, interfaceIndex: service.interfaceIndex),
           let url = ServiceCatalog.url(type: service.type, host: target.host, port: target.port, txt: service.txt) {
            return DiscoveredService(name: service.name, type: service.type, url: url, address: await NetworkProbe.displayAddress(for: target.host))
        }
        guard let address = await resolveAddress(service.endpoint),
              let url = ServiceCatalog.url(type: service.type, host: address.host, port: address.port, txt: service.txt) else { return nil }
        return DiscoveredService(name: service.name, type: service.type, url: url)
    }

    /// Bonjour gives a service name, not an address; connecting briefly over IPv4 reveals the host and port.
    private nonisolated static func resolveAddress(_ endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: parameters)
        let once = Once<(String, Int)?>()
        let address = await withCheckedContinuation { continuation in
            once.set(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                        var name = "\(host)"
                        if let scope = name.firstIndex(of: "%") { name = String(name[..<scope]) }
                        once.resume((name, Int(port.rawValue)))
                    } else {
                        once.resume(nil)
                    }
                case .waiting, .failed: once.resume(nil)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.resume(nil) }
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        return address.map { (host: $0.0, port: $0.1) }
    }

    // MARK: Reachability

    private func checkAll() async {
        async let services: Void = checkServices()
        await check(bookmarks)
        await services
    }

    private func checkServices() async {
        let targets = services.compactMap { service in DiagnosticTarget(url: service.url).map { (service.id, $0) } }
        targets.forEach { serviceStatus[$0.0] = .checking }
        await Self.probe(targets, lookups: []) { [weak self] id, reachability, _, _ in
            self?.serviceStatus[id] = reachability
        }
    }

    private func check(_ bookmarks: [Bookmark]) async {
        let targets = bookmarks.compactMap { bookmark -> (UUID, DiagnosticTarget)? in
            guard let url = BrowserAddress.parse(bookmark.url), let target = DiagnosticTarget(url: url) else { return nil }
            let token = UUID()
            checkTokens[bookmark.id] = token
            checkedURLs[bookmark.id] = bookmark.url
            status[bookmark.id] = .checking
            return (bookmark.id, target)
        }
        let tokens = checkTokens
        let lookups = Set(targets.map(\.1.host).filter { host in
            DeviceStore.isIPAddress(host) && devices.records[DeviceStore.key(host)]?.hostname == nil && reverseLookups.insert(host).inserted
        })
        await Self.probe(targets, lookups: lookups) { [weak self] id, reachability, host, sighting in
            guard let self else { return }
            if checkTokens[id] == tokens[id] {
                status[id] = reachability
                checkTokens[id] = nil
            }
            if sighting.address != nil || sighting.hostname != nil {
                devices.record(address: sighting.address, hostname: sighting.hostname, for: host)
            }
        }
    }

    /// TCP-connects to each target, a few at a time, reporting results as they arrive.
    private static func probe<Key: Sendable>(_ targets: [(Key, DiagnosticTarget)], lookups: Set<String>,
                                             apply: (Key, Reachability, String, NetworkProbe.Sighting) -> Void) async {
        await withTaskGroup(of: (Key, Reachability, String, NetworkProbe.Sighting).self) { group in
            var pending = targets[...]
            func addNext() {
                guard let (key, target) = pending.popFirst() else { return }
                let lookUpName = lookups.contains(target.host)
                group.addTask {
                    let outcome = await NetworkProbe.connect(host: target.host, port: target.port)
                    let sighting = outcome == .connected ? await NetworkProbe.sighting(of: target.host, reverseLookup: lookUpName) : .init()
                    return (key, outcome == .connected ? .reachable : .unreachable, target.host, sighting)
                }
            }
            for _ in 0..<maxConcurrentChecks { addNext() }
            for await (key, reachability, host, sighting) in group {
                apply(key, reachability, host, sighting)
                addNext()
            }
        }
    }
}
