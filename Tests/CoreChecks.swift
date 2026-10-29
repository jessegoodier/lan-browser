import Foundation

@main
struct CoreChecks {
    @MainActor
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
            count += 1
        }
        let valid: [(String, String)] = [
            ("nas.local:8888", "http://nas.local:8888"),
            ("http://nas.local:8888/", "http://nas.local:8888/"),
            ("nas.local:8888/path?q=hello#section", "http://nas.local:8888/path?q=hello#section"),
            ("  server.local  ", "http://server.local"),
            ("192.168.1.20:8080/dashboard", "http://192.168.1.20:8080/dashboard"),
            ("https://example.com/", "https://example.com/"),
            ("HTTP://nas.local:8888/", "HTTP://nas.local:8888/"),
            ("//nas.local:8888/", "http://nas.local:8888/"),
            ("[fd00::1]:8080/", "http://[fd00::1]:8080/")
        ]
        for (input, expected) in valid {
            check(BrowserAddress.parse(input)?.absoluteString == expected, "Address parsing: \(input)")
        }
        for input in ["", "  ", "hello world", "http://", "https://", "ftp://nas.local/", "file:///tmp/a", "http://nas.local:0", "http://nas.local:65536", "http://nas.local:abc", "http://user:password@nas.local/", "nas.local\n:8888"] {
            check(BrowserAddress.parse(input) == nil, "Reject invalid address: \(input)")
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: "LANBrowserChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "bookmarks.json")
        let store = BookmarkStore(fileURL: file)
        check(store.bookmarks.count == 1 && store.bookmarks[0] == .httpForever, "Seed HTTP Forever on first launch")
        let custom = Bookmark(title: "Router", url: "http://192.168.1.1/")
        check(store.save(custom), "Save bookmark")
        var edited = custom
        edited.title = "Home Router"
        edited.url = "https://192.168.1.1/"
        check(store.save(edited), "Edit bookmark")
        check(store.bookmarks.count == 2, "Editing does not duplicate")
        store.move(from: IndexSet(integer: 1), to: 0)
        let reopened = BookmarkStore(fileURL: file)
        check(reopened.bookmarks.first == edited, "Order and edits survive relaunch")
        reopened.delete(at: IndexSet(integer: 0))
        reopened.delete(at: IndexSet(integer: 0))
        check(BookmarkStore(fileURL: file).bookmarks.isEmpty, "Empty bookmarks stay empty after relaunch")
        try Data("not valid json".utf8).write(to: file)
        let corrupt = BookmarkStore(fileURL: file)
        check(corrupt.errorMessage != nil, "Corruption is reported")
        let preserved = try String(contentsOf: file, encoding: .utf8)
        check(preserved == "not valid json", "Corrupt file is not silently overwritten")
        let blocked = directory.appending(path: "not-a-directory")
        try Data().write(to: blocked)
        let failed = BookmarkStore(fileURL: blocked.appending(path: "bookmarks.json"))
        check(failed.errorMessage != nil, "Write errors are reported")
        check(!failed.save(custom), "Failed writes return failure")
        check(!failed.bookmarks.contains(custom), "Failed writes do not claim persistence")

        if CommandLine.arguments.count > 1 {
            let plistTypes = try JSONDecoder().decode([String].self, from: Data(CommandLine.arguments[1].utf8))
            check(plistTypes == ServiceCatalog.types, "NSBonjourServices matches ServiceCatalog.types")
        }
        let mapped: [(String, String, Int, [String: String], String)] = [
            ("_http._tcp", "192.168.1.40", 80, [:], "http://192.168.1.40/"),
            ("_http._tcp", "192.168.1.40", 8080, ["path": "admin"], "http://192.168.1.40:8080/admin"),
            ("_https._tcp", "192.168.1.40", 443, ["path": "/ui"], "https://192.168.1.40/ui"),
            ("_home-assistant._tcp", "192.168.1.5", 8123, [:], "http://192.168.1.5:8123/"),
            ("_plexmediasvr._tcp", "192.168.1.6", 32400, [:], "http://192.168.1.6:32400/web"),
            ("_ipp._tcp", "192.168.1.7", 631, [:], "http://192.168.1.7/"),
            ("_ipps._tcp", "192.168.1.7", 631, [:], "https://192.168.1.7/"),
            ("_octoprint._tcp", "192.168.1.8", 5000, ["path": "/"], "http://192.168.1.8:5000/"),
            ("_esphomelib._tcp", "192.168.1.9", 6053, [:], "http://192.168.1.9/"),
            ("_wled._tcp", "192.168.1.10", 80, [:], "http://192.168.1.10/")
        ]
        for (type, host, port, txt, expected) in mapped {
            check(ServiceCatalog.url(type: type, host: host, port: port, txt: txt)?.absoluteString == expected, "Service URL: \(type)")
        }
        let printerHTTP = DiscoveredService(name: "printer", type: "_http._tcp", url: URL(string: "http://192.168.1.7/")!)
        let printerIPP = DiscoveredService(name: "Office Printer", type: "_ipp._tcp", url: URL(string: "http://192.168.1.7/")!)
        let nas = DiscoveredService(name: "NAS", type: "_http._tcp", url: URL(string: "http://192.168.1.40:5000/")!)
        check(ServiceCatalog.merged([printerHTTP, printerIPP, nas]) == [nas, printerIPP], "Specific service types win duplicates")
        check(ServiceCatalog.merged([printerIPP, printerHTTP]) == [printerIPP], "Duplicate order does not matter")
        let brother = DiscoveredService(name: "Brother", type: "_http._tcp", url: URL(string: "http://brotherE6576F3F.local/")!, address: "10.0.0.232")
        let bookmarkedPrinter = Set(ServiceCatalog.endpointKeys(for: URL(string: "http://10.0.0.232/")!, address: nil))
        check(ServiceCatalog.isBookmarked(brother, bookmarked: bookmarkedPrinter), "Bookmarked IP and port hide a discovered host name")
        check(ServiceCatalog.isBookmarked(brother, bookmarked: Set(ServiceCatalog.endpointKeys(for: URL(string: "http://BrotherE6576F3F.local:80/admin")!, address: nil))), "Host name match ignores case, path, and an explicit default port")
        check(ServiceCatalog.isBookmarked(printerIPP, bookmarked: ["192.168.1.7:80"]), "IP-only discovery matches a bookmarked IP and port")
        let omarchy8888 = Set(ServiceCatalog.endpointKeys(for: URL(string: "http://omarchy.local:8888/")!, address: "10.0.3.46"))
        let omarchy3000 = DiscoveredService(name: "Grafana", type: "_http._tcp", url: URL(string: "http://omarchy.local:3000/")!, address: "10.0.3.46")
        check(!ServiceCatalog.isBookmarked(omarchy3000, bookmarked: omarchy8888), "Another port on a bookmarked device stays listed")
        let omarchyByIP = DiscoveredService(name: "Dev", type: "_http._tcp", url: URL(string: "http://10.0.3.46:8888/")!)
        check(ServiceCatalog.isBookmarked(omarchyByIP, bookmarked: omarchy8888), "Bookmarked host name matches discovery by its last-seen IP")
        check(!ServiceCatalog.isBookmarked(brother, bookmarked: Set(ServiceCatalog.endpointKeys(for: URL(string: "https://10.0.0.232/")!, address: nil))), "HTTPS bookmark on 443 doesn’t hide the HTTP page on 80")
        for host in ["nas.local", "NAS.LOCAL", "nas", "localhost", "10.0.0.2", "172.20.1.1", "192.168.1.1", "169.254.3.4", "127.0.0.1", "fe80::1", "fd00::1", "::1"] {
            check(ServiceCatalog.isLocalHost(host), "Local host: \(host)")
        }
        for host in ["httpforever.com", "8.8.8.8", "172.32.0.1", "192.169.1.1", "2001:db8::1"] {
            check(!ServiceCatalog.isLocalHost(host), "Internet host: \(host)")
        }

        let target = DiagnosticTarget(url: URL(string: "http://nas.local:8080/dashboard")!)!
        check(target.host == "nas.local" && target.port == 8080 && !target.secure && target.path == "/dashboard", "Diagnostic target from URL")
        check(target.hostHeader == "nas.local:8080" && target.isLocal, "Host header keeps a non-default port")
        check(DiagnosticTarget(url: URL(string: "https://[fd00::1]/")!)?.hostHeader == "[fd00::1]", "IPv6 host header uses brackets")
        check(DiagnosticTarget(url: URL(string: "about:blank")!) == nil, "Only HTTP and HTTPS can be diagnosed")
        check(DiagnosticTarget(url: URL(string: "http://10.0.0.5/login.html?next=%2F")!)?.path == "/login.html?next=%2F", "Request path keeps the query")
        let base = URL(string: "http://10.0.0.1/")!
        check(Redirects.next(from: base, status: 301, location: "https://10.0.0.1/")?.absoluteString == "https://10.0.0.1/", "Absolute redirect")
        check(Redirects.next(from: base, status: 302, location: "/login?x=1")?.absoluteString == "http://10.0.0.1/login?x=1", "Relative redirect resolves against the page")
        check(Redirects.next(from: base, status: 304, location: "/") == nil && Redirects.next(from: base, status: 200, location: "/") == nil, "304 and 200 aren’t redirects")
        let response = "HTTP/1.1 404 Not Found\r\nserver: nginx/1.25\r\nContent-Length: 0\r\n\r\nServer: body"
        check(DiagnosticsText.statusCode(in: response) == 404, "Parse HTTP status code")
        check(DiagnosticsText.header("Server", in: response) == "nginx/1.25", "Parse header case-insensitively, ignoring the body")
        check(DiagnosticsText.statusCode(in: "SSH-2.0-OpenSSH_9.6\r\n") == nil, "Non-HTTP banner has no status")
        check(DiagnosticsText.advice(for: .refused, target: target).contains("port 8080"), "Refused advice names the port")
        check(DiagnosticsText.advice(for: .nameNotFound, target: target).contains(".local"), "Lookup advice explains .local names")
        let steps = [DiagnosticStep(kind: .network, status: .passed, detail: "Wi-Fi"), DiagnosticStep(kind: .port, status: .failed, detail: "Refused", advice: "Start it.")]
        let report = DiagnosticsText.report(url: URL(string: "http://nas.local:8080/")!, steps: steps)
        check(report.contains("✓ Network: Wi-Fi") && report.contains("✗ Port: Refused\n  Start it."), "Report lists each step and advice")

        check(DeviceStore.key("Omarchy.LOCAL.") == "omarchy.local" && DeviceStore.key("[FD00::1]") == "fd00::1", "Device keys are normalized")
        check(DeviceStore.isIPAddress("10.0.2.2") && DeviceStore.isIPAddress("fd00::1") && !DeviceStore.isIPAddress("omarchy.local") && !DeviceStore.isIPAddress("1.2.3.999"), "Detect IP addresses")
        check(DeviceStore.defaultName(for: "omarchy.local") == "omarchy", "Default name drops .local")
        check(DeviceStore.defaultName(for: "10.0.0.232", hostname: "brothere6576f3f.localdomain.") == "brothere6576f3f", "IP uses reverse-lookup name")
        check(DeviceStore.defaultName(for: "10.0.0.232") == "10.0.0.232" && DeviceStore.defaultName(for: "httpforever.com") == "httpforever.com", "Default name falls back to the host")
        let devicesFile = directory.appending(path: "devices.json")
        let devices = DeviceStore(fileURL: devicesFile)
        let omarchy = URL(string: "http://omarchy.local:8888/")!
        check(devices.label(for: omarchy) == "omarchy:8888", "Label without a known IP")
        devices.record(address: "10.0.2.2", for: "omarchy.local")
        check(devices.label(for: omarchy) == "omarchy:8888 · 10.0.2.2", "Label shows name, port, and IP")
        check(devices.label(for: URL(string: "http://omarchy.local:32400/web")!) == "omarchy:32400/web · 10.0.2.2", "Label keeps the path")
        check(devices.rename("OMARCHY.local", to: "  Desk PC "), "Rename device")
        check(devices.label(for: omarchy) == "Desk PC:8888 · 10.0.2.2", "Custom name is shared across host spellings")
        devices.record(address: "10.0.2.9", for: "omarchy.local")
        let reloaded = DeviceStore(fileURL: devicesFile)
        check(reloaded.label(for: omarchy) == "Desk PC:8888 · 10.0.2.9", "Name survives an IP change and relaunch")
        check(reloaded.rename("omarchy.local", to: "") && reloaded.customName(for: "omarchy.local") == nil, "Empty name restores the default")
        check(reloaded.rename("omarchy.local", to: "omarchy") && reloaded.customName(for: "omarchy.local") == nil, "Default name is not stored as custom")
        reloaded.record(address: "10.0.0.232", for: "10.0.0.232")
        check(reloaded.label(for: URL(string: "http://10.0.0.232/")!) == "10.0.0.232", "IP bookmarks don’t repeat the IP")
        reloaded.record(hostname: "brothere6576f3f.localdomain", for: "10.0.0.232")
        check(reloaded.label(for: URL(string: "http://10.0.0.232/")!) == "brothere6576f3f", "IP bookmark shows reverse-lookup name")
        check(reloaded.label(for: URL(string: "http://nas.local/")!, address: "10.0.0.5") == "nas · 10.0.0.5", "Discovery address is used when none is stored")

        check(!TabPolicy.opensNewTab(currentTabIsBlank: true, preference: .newTab), "A blank tab is filled, not left behind")
        check(TabPolicy.opensNewTab(currentTabIsBlank: false, preference: .newTab), "New Tab preference opens a tab")
        check(!TabPolicy.opensNewTab(currentTabIsBlank: false, preference: .currentTab), "Current Tab preference replaces the page")
        let tabStore = TabStore(fileURL: directory.appending(path: "tabs.json"))
        check(tabStore.load() == nil, "No saved tabs on first launch")
        let savedTabs = SavedTabs(tabs: [
            SavedTab(id: UUID(), url: "http://omarchy.local:8888/", title: "Grafana", state: Data([1, 2, 3])),
            SavedTab(id: UUID(), url: nil, title: "", state: nil)
        ], selected: 7)
        tabStore.save(savedTabs)
        let loadedTabs = tabStore.load()
        check(loadedTabs?.tabs == savedTabs.tabs, "Tabs and their history survive relaunch")
        check(loadedTabs?.selected == 1, "Selected tab index is clamped")
        tabStore.clear()
        check(tabStore.load() == nil, "Clearing removes saved tabs")
        try Data("{".utf8).write(to: tabStore.fileURL)
        check(tabStore.load() == nil, "Damaged tab file starts fresh")

        let cache = DiscoveryCache(fileURL: directory.appending(path: "discovered.json"))
        check(cache.load() == nil, "No discovery cache before the first scan")
        let scan = DiscoveryScan(date: Date(timeIntervalSince1970: 1_800_000_000), network: "en0|10.0.0.1", services: [nas, printerIPP])
        cache.save(scan)
        check(cache.load() == scan, "Last scan survives relaunch")
        var trimmed = scan
        trimmed.services.removeAll { $0.id == nas.id }
        cache.save(trimmed)
        check(cache.load()?.services == [printerIPP], "Removing one result is saved")
        cache.clear()
        check(cache.load() == nil, "Clear Results deletes the cache")

        check(PortScanPreset.off.ports.isEmpty && PortScanPreset.standard.ports == [80, 443], "Off and Standard port lists")
        check(PortScanPreset.common.ports.count == 22 && Set(PortScanPreset.common.ports).count == 22 && PortScanPreset.common.ports.contains(32400), "Common list has 22 distinct ports")
        let lan = IPv4Range(cidr: "10.0.2.183/22")!
        check(lan.cidr == "10.0.0.0/22" && lan.count == 1022 && lan.description == "10.0.0.1 – 10.0.3.254", "Parse a /22 from any address in it")
        let lanHosts = lan.hosts(excluding: "10.0.2.183")
        check(lanHosts.count == 1021 && lanHosts.first == "10.0.0.1" && lanHosts.last == "10.0.3.254" && !lanHosts.contains("10.0.2.183"), "Hosts skip network, broadcast and the phone")
        check(IPv4Range.scanRange(network: "10.0.0.0/22", deviceIP: "10.0.2.183") == lan, "Networks up to 1,024 addresses are scanned whole")
        check(IPv4Range.scanRange(network: "172.16.0.0/16", deviceIP: "172.16.9.40")?.cidr == "172.16.9.0/24", "Large networks fall back to the phone’s /24")
        check(IPv4Range(cidr: "10.0.0.1/32")?.hosts().isEmpty == true && IPv4Range(cidr: "nonsense") == nil && IPv4Range(cidr: "10.0.0.256/24") == nil, "Reject unusable ranges")
        let plan = PortScanPlan(preset: .common, range: lan, deviceIP: "10.0.2.183")
        check(plan.addressCount == 1021 && plan.discoveryConnections == 2042, "Plan counts addresses and pass-1 connections")
        check(plan.needsConfirmation(confirmedCount: nil) && !plan.needsConfirmation(confirmedCount: 1021) && !plan.needsConfirmation(confirmedCount: 4000) && plan.needsConfirmation(confirmedCount: 253), "Confirm again only for a larger network")
        check(PortScan.prefersHTTPS(port: 9443) && !PortScan.prefersHTTPS(port: 9000), "HTTPS-first ports")
        check(DiagnosticsText.htmlTitle(in: "HTTP/1.1 200 OK\r\n\r\n<html><head><TITLE lang=en>\n  Portainer &amp; Co\n</TITLE>") == "Portainer & Co", "Page title, any case, entities decoded")
        check(DiagnosticsText.htmlTitle(in: "<html><title></title>") == nil && DiagnosticsText.htmlTitle(in: "no html") == nil, "Missing title")
        let scannedPrinter = DiscoveredService(name: "Brother Admin", type: "_http._tcp", url: URL(string: "http://10.0.0.232/")!, foundBy: .portScan)
        let scannedGrafana = DiscoveredService(name: "Grafana", type: "_http._tcp", url: URL(string: "http://10.0.3.46:3000/")!, foundBy: .portScan)
        check(ServiceCatalog.mergedWithScan(bonjour: [brother], scanned: [scannedPrinter, scannedGrafana]) == [brother, scannedGrafana], "Bonjour wins over the same address and port")
        func finding(_ url: String, _ status: Int, title: String? = nil, server: String? = nil, location: String? = nil) -> WebFinding {
            let parsed = URL(string: url)!
            return WebFinding(host: parsed.host!, port: ServiceCatalog.port(of: parsed), url: parsed, status: status, title: title, server: server, location: location)
        }
        let unifiRedirect = finding("http://10.0.0.1/", 301, title: "301 Moved Permanently", location: "https://10.0.0.1/")
        let unifi = finding("https://10.0.0.1/", 200, title: "UniFi OS")
        let badRequest = finding("http://10.0.0.1:8080/", 400, title: "HTTP Status 400 – Bad Request")
        let loginRedirect = finding("http://10.0.0.5/", 302, server: "gSOAP/2.8", location: "/login.html")
        let lighttpdHTTP = finding("http://10.0.2.202/", 200, server: "lighttpd/1.4.54")
        let lighttpdHTTPS = finding("https://10.0.2.202/", 200, server: "lighttpd/1.4.54")
        let collapsed = PortScan.collapse([unifiRedirect, unifi, badRequest, loginRedirect, lighttpdHTTP, lighttpdHTTPS])
        check(collapsed == [unifi, loginRedirect, lighttpdHTTPS], "Drop 400s, redirects to found pages, and HTTP copies of HTTPS pages")
        check(PortScan.collapse([unifiRedirect]) == [unifiRedirect], "A redirect to a page that wasn’t found is kept")
        check(PortScan.name(for: unifi, deviceName: "unifi") == "UniFi OS", "Page title names the row")
        check(PortScan.name(for: loginRedirect, deviceName: "camera") == "camera", "Redirects use the device name, not the placeholder title")
        check(PortScan.name(for: finding("http://10.0.3.46:3000/", 200), deviceName: "omarchy") == "omarchy:3000", "Device name keeps a non-web port")
        check(PortScan.name(for: lighttpdHTTPS, deviceName: nil) == "lighttpd/1.4.54", "Server software when nothing better")
        check(PortScan.name(for: finding("http://10.0.3.166/", 200), deviceName: nil) == "Web app on port 80", "Port as the last resort")
        check(HTTPStatus.line(404) == "404 Not Found" && HTTPStatus.line(503) == "503 Service Unavailable" && HTTPStatus.line(599) == "599", "Status lines use standard phrases, or just the code")
        let notFound = PageResponse(method: "GET", url: "http://omarchy.local:8888/missing", statusCode: 404,
                                    headers: [ResponseHeader(name: "Content-Length", value: "0"), ResponseHeader(name: "Server", value: "nginx/1.25")])
        check(notFound.isError && notFound.header("server") == "nginx/1.25", "Response header lookup ignores case")
        check(notFound.report == "GET http://omarchy.local:8888/missing\nStatus: 404 Not Found\n\nContent-Length: 0\nServer: nginx/1.25", "Response report is verbatim")
        check(notFound.summary == "GET http://omarchy.local:8888/missing\nContent-Length: 0\nServer: nginx/1.25", "Error summary lists request and key headers")
        check(ErrorText.details(domain: "NSURLErrorDomain", code: -1004, url: "http://10.0.0.5:81/", underlying: (domain: "kCFErrorDomainCFNetwork", code: -1004))
              == "Error: NSURLErrorDomain -1004\nUnderlying: kCFErrorDomainCFNetwork -1004\nURL: http://10.0.0.5:81/", "Load errors show exact domain, code and URL")
        check(BlockedPorts.message(for: URL(string: "http://nas.local:22/")!)?.contains("port 22") == true, "SSH port is explained, not left blank")
        check(BlockedPorts.message(for: URL(string: "http://nas.local:8080/")!) == nil && BlockedPorts.message(for: URL(string: "http://nas.local/")!) == nil, "Web ports load normally")
        let oldCache = Data(#"{"name":"NAS","type":"_http._tcp","url":"http://nas.local/"}"#.utf8)
        check((try? JSONDecoder().decode(DiscoveredService.self, from: oldCache))?.foundBy == nil, "Scans saved before port scanning still load")
        print("Passed \(count) core checks (address parsing, bookmark persistence, discovery, diagnostics, device names, tabs, and port scan).")
    }
}
